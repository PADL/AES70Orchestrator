# AES70Orchestrator

A Swift framework for orchestrating [AES70/OCA](https://ocaalliance.com) devices using profiles — virtual representations of device configurations that can be created offline, bound to physical devices at runtime, and serialised for persistence.

Built on [SwiftOCA](https://github.com/PADL/SwiftOCA).

## Overview

AES70Orchestrator lets you describe a device's object hierarchy in YAML, then create an arbitrary number of **profiles** that match that schema. Each profile gets its own block hierarchy of local proxy objects that you can manipulate as you would on any OCA device — without a physical device being present.

The key feature is **device binding**: you can bind a profile to one or more remote devices. The `match` property in the YAML schema describes which object numbers on the remote device to target, and the mask determines how many profiles can be bound to a single device. Once bound, property change events are forwarded bidirectionally between local proxy objects and their corresponding remote device objects.

### Use case

A profile represents an end-user of a personal monitor mixer. Each mixer can support multiple users (reflected in the match mask). This enables:

- **Offline provisioning** — create and configure user profiles without any device connected
- **User mobility** — move users and their mix settings between devices by rebinding profiles
- **State persistence** — serialise all device bindings and profile parameter sets, retrievable over OCA

## Device schema

Devices are described in YAML. Here is an example matching SwiftOCA's `OCADevice` example:

```yaml
# Block (ONo 10000)
#   BooleanActuator x8 (ONos 10010..10017)
#   Gain (ONo 10020)
device:
  name: OCADevice

  profiles:
    - OCADevice:
      - Block:
          classID: 1.1.3
          match: 0x00002710/0x00000000
          objectNumber: 0x00001000/0x000000F0
          actionObjects:
            - "Actuator(0,0)":
                classID: 1.1.1.1.1
                match: 0x0000271A/0x00000000
                objectNumber: 0x00002000/0x000000F0
            # ... more actuators ...
            - Gain:
                classID: 1.1.1.5
                match: 0x00002724/0x00000000
                objectNumber: 0x00002010/0x000000F0
```

Each object in the schema specifies:

- **`classID`** — dotted OCA class ID (e.g. `1.1.1.5` for `OcaGain`), resolved via the device class registry. Omit for containers with children (inferred as `OcaBlock`) or leaves (inferred as `OcaRoot`).
- **`match`** — remote object number and mask (`oNo/mask`). The mask bits determine how many profile instances can be bound to a single device.
- **`objectNumber`** — optional local object number and mask for the proxy object.

## Architecture

The framework exposes an OCA device with the following structure:

- **OcaCoordinator** (ONo 1024) — an `OcaManager` that manages profiles. Provides OCP.1 methods for creating, binding, finding, and deleting profiles, as well as exporting/importing state.
- **Profiles block** (ONo 1025) — contains `OcaProfile` agents, one per created profile.
- **Profile Proxies block** (ONo 1026) — contains per-schema sub-blocks, each containing per-profile sub-blocks with the local proxy objects that mirror the device schema.

Each `OcaProfile` is an `OcaAgent` with:
- A read-only `schema` property identifying which device schema it belongs to
- A read-only `boundDevices` list
- A proxy block containing the local object hierarchy matching the schema

The profile's label is synchronised from its proxy block — set the label on the proxy block and it propagates to the profile.

## Modules

- **AES70Orchestrator** — server-side (device) library
- **AES70OrchestratorClient** — client-side controller library with `@OcaProperty` declarations and `sendCommandRrq`-based methods

## Persistence

State can be saved to and loaded from ZIP archives (file-based or in-memory `OcaLongBlob`). The archive contains a JSON manifest of profiles and their device bindings, plus serialised parameter datasets for each profile's proxy block. State export/import is also accessible over OCP.1.

## Dependencies

- [SwiftOCA](https://github.com/PADL/SwiftOCA) — OCA/OCP.1 implementation
- [Yams](https://github.com/jpsim/Yams) — YAML schema parsing
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — persistence archives
- [swift-log](https://github.com/apple/swift-log) — logging
- [swift-async-algorithms](https://github.com/apple/swift-async-algorithms) — debounced persistence monitor

## License

Apache License 2.0. See [LICENSE.txt](LICENSE.txt).
