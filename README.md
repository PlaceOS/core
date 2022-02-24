# PlaceOS Core

[![Build](https://github.com/PlaceOS/core/actions/workflows/build.yml/badge.svg)](https://github.com/PlaceOS/core/actions/workflows/build.yml)
[![CI](https://github.com/PlaceOS/core/actions/workflows/ci.yml/badge.svg)](https://github.com/PlaceOS/core/actions/workflows/ci.yml)

The coordination service for running drivers on [PlaceOS](https://place.technology).

## Implementation

### Cloning

Core handles the cloning of driver repositories.
If a repository is already present on the file system, its git state is adjusted to match the model's commit.

### Compilation

Compilation of drivers is performed on all core nodes.

### Module Management

Modules are instantiations of drivers which are distributed across core nodes through [rendezvous hashing](https://github.com/aca-labs/hound-dog).

### Clustering

Core is a clustered service. This is implemented through the [clustering](https://github.com/aca-labs/clustering) lib.

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md).
