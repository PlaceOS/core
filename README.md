# PlaceOS Core

[![Build](https://github.com/PlaceOS/core/actions/workflows/build.yml/badge.svg)](https://github.com/PlaceOS/core/actions/workflows/build.yml)
[![CI](https://github.com/PlaceOS/core/actions/workflows/ci.yml/badge.svg)](https://github.com/PlaceOS/core/actions/workflows/ci.yml)

The coordination service for running drivers on [PlaceOS](https://place.technology).

## Implementation

### Compilation

Compilation of drivers and binary management is performed by `build-api` service.

### Module Management

Modules are instantiations of drivers which are distributed across core nodes through [rendezvous hashing](https://github.com/aca-labs/hound-dog).

### Clustering

Core is a clustered service. This is implemented through the [clustering](https://github.com/aca-labs/clustering) lib.

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md).
