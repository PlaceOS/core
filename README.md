# PlaceOS Core

[![Build Status](https://travis-ci.com/placeos/core.svg?branch=master)](https://travis-ci.com/placeos/core)

The coordination service for running drivers on [PlaceOS](https://place.technology).

## Implementation

### Cloning

During core's startup process, [driver repositories](https://github.com/placeos/drivers) are cloned. If they're already present on the file system, they are pulled and the driver dependencies installed.
When the repository model is out of date, it's commit hash is updated to the commit of the local head.

### Compilation

Compilation of drivers occurs across each core node on startup.

### Module Management

Modules are instantiations of drivers which are started depending on whether the module id maps the current node through [rendezvous hashing](https://github.com/aca-labs/hound-dog).

### Clustering

Core is a clustered service. This is implemented through the [clustering](https://github.com/aca-labs/clustering) lib.
