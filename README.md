# Crystal Lang Engine Core

[![Build Status](https://travis-ci.org/aca-labs/crystal-engine-core.svg?branch=master)](https://travis-ci.org/aca-labs/crystal-engine-core)

The coordination service for running drivers on Crystal-Engine.

## Implementation

### Cloning

During core's startup process, [driver repositories](https://github.com/aca-labs/crystal-engine-drivers) are cloned. If they're already present on the file system, they are pulled and the driver dependencies installed.
When the repository model is out of date, it's commit hash is updated to the commit of the local head.

### Compilation

Compilation of drivers occurs across each core node on startup.

### Module Management

Modules are instantiations of drivers which are started depending on whether the module id maps the current node through [https://github.com/aca-labs/hound-dog](rendezvous hashing).
