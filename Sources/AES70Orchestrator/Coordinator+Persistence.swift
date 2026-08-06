//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import AsyncAlgorithms
import Foundation
import SwiftOCA
@_spi(SwiftOCAPrivate) import SwiftOCADevice
import ZIPFoundation

private let ArchiveVersion = "v0"

private struct _ProfileManifestBinding: Codable {
  let deviceID: String
  let deviceIndex: OcaONo?
}

private struct _ProfileManifestEntry: Codable {
  let name: String?
  let bindings: [_ProfileManifestBinding]
  let devices: [String]?

  init(name: String?, bindings: [_ProfileManifestBinding]) {
    self.name = name
    self.bindings = bindings
    devices = nil
  }

  var restoredBindings: [_ProfileManifestBinding] {
    if !bindings.isEmpty {
      return bindings
    }
    return (devices ?? []).map { deviceID in
      _ProfileManifestBinding(deviceID: deviceID, deviceIndex: nil)
    }
  }
}

extension OcaCoordinator {
  private func _manifestPath(for schemaName: String) -> String {
    "\(ArchiveVersion)/\(schemaName)/MANIFEST"
  }

  private func _profileStatePath(for schemaName: String, uuid: String) -> String {
    "\(ArchiveVersion)/\(schemaName)/\(uuid)"
  }

  private func _addEntry(
    to archive: Archive,
    path: String,
    data: Data
  ) throws {
    try archive.addEntry(
      with: path,
      type: .file,
      uncompressedSize: Int64(data.count),
      compressionMethod: .deflate
    ) { position, size in
      data.subdata(in: Int(position)..<(Int(position) + size))
    }
  }

  /// Write profile state to `archive`. When `including` is non-`nil`, only
  /// profiles whose object number it contains are written, and schemas left
  /// with no profiles are omitted from the archive entirely — such a partial
  /// archive is meant to be imported with `clearExisting: false`, since
  /// replace-all would drop the profiles it does not mention.
  private func _save(to archive: Archive, including: Set<OcaONo>? = nil) async throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    for (schemaName, entry) in _schemaEntries {
      let profiles = entry.profiles.actionObjects.filter {
        including?.contains($0.objectNumber) ?? true
      }
      guard !profiles.isEmpty else { continue }

      // build devices.json manifest
      var manifest = [String: _ProfileManifestEntry]()
      for profile in profiles {
        let uuid = profile.role
        manifest[uuid] = _ProfileManifestEntry(
          name: profile.label,
          bindings: profile.boundDevices.map { deviceID in
            _ProfileManifestBinding(
              deviceID: deviceID,
              deviceIndex: profile.boundDeviceIndices[deviceID]
            )
          }
        )
      }
      let devicesData = try encoder.encode(manifest)
      try _addEntry(to: archive, path: _manifestPath(for: schemaName), data: devicesData)

      // serialize each profile's state with ONo remapping
      for profile in profiles {
        guard profile.proxyBlock != nil else { continue }
        let jsonObject = try await profile.serializeState()
        let stateData = try JSONSerialization.data(
          withJSONObject: jsonObject,
          options: [.prettyPrinted, .sortedKeys]
        )
        try _addEntry(
          to: archive,
          path: _profileStatePath(for: schemaName, uuid: profile.role),
          data: stateData
        )
      }
    }
  }

  private func _load(from archive: Archive, clearExisting: Bool) async throws {
    let decoder = JSONDecoder()

    if clearExisting {
      try await _deleteAllProfiles()
    }

    for (schemaName, _) in _schemaEntries {
      // read manifest
      let devicesPath = _manifestPath(for: schemaName)
      guard let devicesEntry = archive[devicesPath] else { continue }

      var devicesData = Data()
      _ = try archive.extract(devicesEntry) { data in
        devicesData.append(data)
      }
      let manifest = try decoder.decode(
        [String: _ProfileManifestEntry].self,
        from: devicesData
      )

      // recreate each profile
      for (uuidString, entry) in manifest {
        guard let uuid = UUID(uuidString: uuidString) else {
          logger.warning("load: invalid UUID \(uuidString)")
          continue
        }
        // merge mode (clearExisting == false): skip profiles that already exist
        // rather than aborting the whole load on a uniqueness conflict
        if !clearExisting, (try? findProfile(uuid: uuid)) != nil {
          logger.debug("load: skipping already-present profile \(uuidString)")
          continue
        }
        let profileONo = try await _addProfile(schema: schemaName, name: entry.name, uuid: uuid)
        let profile = try _findProfile(oNo: profileONo)

        // restore profile state before binding so local objects have their
        // saved values when _copyProperties runs at bind time
        guard profile.proxyBlock != nil else { continue }
        let statePath = _profileStatePath(for: schemaName, uuid: uuidString)
        if let stateEntry = archive[statePath] {
          var stateData = Data()
          _ = try archive.extract(stateEntry) { data in
            stateData.append(data)
          }
          if let jsonObject = try JSONSerialization.jsonObject(
            with: stateData
          ) as? [String: any Sendable] {
            do {
              logger.debug(
                "load: deserializing profile \(uuidString) schema=\(schemaName) stateBytes=\(stateData.count) bindings=\(entry.restoredBindings.map(\.deviceID))"
              )
              try await profile.deserializeState(jsonObject)
              logger.debug(
                "load: deserialized profile \(uuidString) schema=\(schemaName) profileONo=\(profile.objectNumber) proxyBlockONo=\(profile.proxyBlock?.objectNumber ?? OcaInvalidONo)"
              )
            } catch {
              logger
                .warning("load: failed to deserialize state for profile \(uuidString): \(error)")
            }
          } else {
            logger.warning("load: invalid state data for profile \(uuidString)")
          }
        } else {
          logger.warning("load: missing state entry for profile \(uuidString)")
        }

        // restore bound devices after state so _copyProperties sends saved values.
        // Index allocation stays ordered and synchronous; activation is all network
        // I/O against independent connections, so it runs concurrently per device.
        if profile.isAutomaticallyBound, !entry.restoredBindings.isEmpty {
          throw OcaCoordinatorError.profileAutomaticallyBound
        }
        var boundDevices = [OcaConnectionBroker.DeviceIdentifier]()
        for binding in entry.restoredBindings {
          guard let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(binding.deviceID) else {
            logger.warning("load: invalid device identifier \(binding.deviceID)")
            continue
          }
          try _bindProfile(profile, to: deviceIdentifier, deviceIndex: binding.deviceIndex)
          boundDevices.append(deviceIdentifier)
        }
        await withDiscardingTaskGroup { group in
          for deviceIdentifier in boundDevices
            where profile.remoteObjectCount(for: deviceIdentifier) == 0
          {
            group.addTask { await self._activateProfile(profile, to: deviceIdentifier) }
          }
        }
        logger.trace("Loaded profile \(uuidString) for schema \(schemaName)")
      }
    }

    // recreate any automatically-bound profiles not present in the archive
    try await _ensureAutobindProfiles()
  }

  private func _export(to url: URL, including: Set<OcaONo>?) async throws {
    let tempURL = url.appendingPathExtension(UUID().uuidString)
    do {
      let archive = try Archive(url: tempURL, accessMode: .create)
      try await _save(to: archive, including: including)
      _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    } catch {
      // don't leave a partial temp archive behind on failure
      try? FileManager.default.removeItem(at: tempURL)
      throw error
    }
    logger.debug("Saved state to \(url.path)")
  }

  public func export(to url: URL) async throws {
    try await _export(to: url, including: nil)
  }

  /// Export only `profiles` to a ZIP archive on disk. Import the result with
  /// `clearExisting: false` to merge it into an existing coordinator.
  public func export(profiles: some Sequence<OcaProfile>, to url: URL) async throws {
    try await _export(to: url, including: Set(profiles.map(\.objectNumber)))
  }

  /// Export `profile` together with every profile sharing a bound device with
  /// it — see ``OcaCoordinator/profiles(relatedTo:transitive:)``.
  public func export(
    relatedTo profile: OcaProfile,
    transitive: Bool = false,
    to url: URL
  ) async throws {
    try await export(profiles: profiles(relatedTo: profile, transitive: transitive), to: url)
  }

  /// Import state from a ZIP archive on disk. When `clearExisting` is `true`
  /// (the default), all existing profiles are deleted first (replace-all).
  /// When `false`, profiles whose UUID already exists are skipped (merge).
  public func `import`(from url: URL, clearExisting: Bool = true) async throws {
    let archive = try Archive(url: url, accessMode: .read)
    try await _load(from: archive, clearExisting: clearExisting)
    logger.debug("Loaded state from \(url.path)")
  }

  private func _export(including: Set<OcaONo>?) async throws -> OcaLongBlob {
    let archive = try Archive(data: Data(), accessMode: .create)
    try await _save(to: archive, including: including)
    guard let data = archive.data else {
      throw OcaCoordinatorError.persistenceError
    }
    var blob = OcaLongBlob()
    blob.wrappedValue = data
    logger.debug("Saved state to blob (\(data.count) bytes)")
    return blob
  }

  public func export() async throws -> OcaLongBlob {
    try await _export(including: nil)
  }

  /// Export only `profiles` as an in-memory ZIP archive blob. Import the result
  /// with `clearExisting: false` to merge it into an existing coordinator.
  public func export(profiles: some Sequence<OcaProfile>) async throws -> OcaLongBlob {
    try await _export(including: Set(profiles.map(\.objectNumber)))
  }

  /// Export `profile` together with every profile sharing a bound device with
  /// it — see ``OcaCoordinator/profiles(relatedTo:transitive:)``.
  ///
  /// This is the "take this profile and everything configured alongside it"
  /// operation: for a mixer, seeding with an input profile yields that profile
  /// plus the user profiles bound to the same devices.
  public func export(
    relatedTo profile: OcaProfile,
    transitive: Bool = false
  ) async throws -> OcaLongBlob {
    try await export(profiles: profiles(relatedTo: profile, transitive: transitive))
  }

  /// Import state from an in-memory ZIP archive blob. When `clearExisting` is
  /// `true` (the default), all existing profiles are deleted first (replace-all).
  /// When `false`, profiles whose UUID already exists are skipped (merge).
  public func `import`(from blob: OcaLongBlob, clearExisting: Bool = true) async throws {
    let archive = try Archive(data: blob.wrappedValue, accessMode: .read)
    try await _load(from: archive, clearExisting: clearExisting)
    logger.debug("Loaded state from blob (\(blob.wrappedValue.count) bytes)")
  }
}
