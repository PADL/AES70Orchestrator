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

  private func _save(to archive: Archive) async throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    for (schemaName, entry) in _schemaEntries {
      // build devices.json manifest
      var manifest = [String: _ProfileManifestEntry]()
      for profile in entry.profiles.actionObjects {
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
      for profile in entry.profiles.actionObjects {
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

  private func _load(from archive: Archive) async throws {
    let decoder = JSONDecoder()

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
        let profileONo = try await addProfile(schema: schemaName, name: entry.name, uuid: uuid)
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
              logger.warning("load: failed to deserialize state for profile \(uuidString): \(error)")
            }
          } else {
            logger.warning("load: invalid state data for profile \(uuidString)")
          }
        } else {
          logger.warning("load: missing state entry for profile \(uuidString)")
        }

        // restore bound devices after state so _copyProperties sends saved values
        for binding in entry.restoredBindings {
          guard let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(binding.deviceID) else {
            logger.warning("load: invalid device identifier \(binding.deviceID)")
            continue
          }
          try await bindProfile(profile, to: deviceIdentifier, deviceIndex: binding.deviceIndex)
        }
        logger.trace("Loaded profile \(uuidString) for schema \(schemaName)")
      }
    }
  }

  public func export(to url: URL) async throws {
    let tempURL = url.appendingPathExtension(UUID().uuidString)
    let archive = try Archive(url: tempURL, accessMode: .create)
    try await _save(to: archive)
    _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    logger.debug("Saved state to \(url.path)")
  }

  public func `import`(from url: URL) async throws {
    let archive = try Archive(url: url, accessMode: .read)
    try await _load(from: archive)
    logger.debug("Loaded state from \(url.path)")
  }

  public func export() async throws -> OcaLongBlob {
    let archive = try Archive(data: Data(), accessMode: .create)
    try await _save(to: archive)
    guard let data = archive.data else {
      throw OcaCoordinatorError.persistenceError
    }
    var blob = OcaLongBlob()
    blob.wrappedValue = data
    logger.debug("Saved state to blob (\(data.count) bytes)")
    return blob
  }

  public func `import`(from blob: OcaLongBlob) async throws {
    let archive = try Archive(data: blob.wrappedValue, accessMode: .read)
    try await _load(from: archive)
    logger.debug("Loaded state from blob (\(blob.wrappedValue.count) bytes)")
  }
}
