## v4.0.0 (2022-02-24)

### Refactor

- **edge/client**: update secret, remove `edge_id` ([#162](https://github.com/PlaceOS/core/pull/162))
- central build ci ([#159](https://github.com/PlaceOS/core/pull/159))
- **process_manager**: load errors messages ([#154](https://github.com/PlaceOS/core/pull/154))

### Feat

- add support for custom response codes ([#161](https://github.com/PlaceOS/core/pull/161))
- **api/command**: propagate `user_id` ([#153](https://github.com/PlaceOS/core/pull/153))
- **drivers**: persist driver bins and repos across container recreation ([#142](https://github.com/PlaceOS/core/pull/142))

### Fix

- **api command**: ensure debug writes are serialised ([#146](https://github.com/PlaceOS/core/pull/146))
- **api command**: obtain latest process manager to ignore ([#144](https://github.com/PlaceOS/core/pull/144))
- **edge**: handle proxied PUBLISH events
- reconnection
- **api:drivers**: account for branch in commit listing
- bump placeos-compiler
- **process_manager/local**: reduce severity of missing mod manager log
- driver compilation from non-default branches
- **resource:cloning**: decrypt password on use

## v3.11.0 (2021-07-29)

### Feat

- **client**: add debug method returning websocket ([#119](https://github.com/PlaceOS/core/pull/119))

### Refactor

- **client**: improve client for use with driver ([#118](https://github.com/PlaceOS/core/pull/118))

## v3.10.6 (2021-07-20)

### Fix

- **core client**: wait for response to complete

## v3.10.5 (2021-07-20)

### Fix

- **core client**: ensure body has completely downloaded
- **core client**: ensure body has completely downloaded

### Feat

- **shard.yml**: bump version

## v3.10.3 (2021-07-19)

### Fix

- **client/core**: allow empty initializer for DriverStatus

## v3.10.1 (2021-07-09)

### Refactor

- move controllers to an api folder
- **client**: tidy up
- clean up Log contexts
- **managers**: less noise in handlers

### Fix

- **module_manager**: pass repository to compiled check
- **Dockerfile**: add yaml-static

### Feat

- embed curl in CLI

## v3.10.0 (2021-06-28)

### Fix

- **logging**: set progname

### Refactor

- remove a set of NamedTuples from code base
- **controller/drivers**: use a more explicit id param
- **config**: extract logging to logging.cr

### Feat

- **core/client:branches**: add branches to client
- **controller/drivers**: add branch listing

## v3.8.1 (2021-04-26)

### Fix

- **settings_update**: ensure non-erroring settings updates complete
- drop excess libssh2 libs
- **logging**: fix logstash logging, ensure consistent logs at startup

### Refactor

- **spec**: stop using a global ResourceManager instance
- **root**: pull readiness check out of controller

### Feat

- support branch switching
- **controllers:command**: trace log when adding a debug session
- add verbose signalling
- add cause to raised Resource::ProcessingError
- **controller:root**: better healthcheck
- **resource:compilation**: add failed compilation output to the driver

### Perf

- **module_manager**: allocate an array of batch size
- **module_manager**: parallel load of modules during stabilization

## v3.4.0 (2021-03-08)

### Refactor

- use driver binary name rather than path

### Fix

- **module_manager**: prevent multiple stabilisations via lock

## v3.3.0 (2021-02-25)

### Refactor

- use placeos log backend

### Feat

- **process_manager**: add system_model callback

### Fix

- **config**: report logs in milliseconds only

## v3.2.0 (2021-02-17)

### Feat

- add logstash support

### Fix

- **process_manager:local**: make manager lock reentrant
- **module_manager**: reload module while preserving debug callbacks
- **controller:command**: remove callback on socket close
- **edge:protocol**: account for new serializer descriminator semantics

## v3.0.0 (2021-01-15)

### Feat

- edge ([#47](https://github.com/PlaceOS/core/pull/47))

### Fix

- dev builds

## v2.5.10 (2020-12-03)

### Fix

- ensure module manager starts in resource manager callback
- **test**: remove container names from docker-compose
- **log**: bind to correct log namespace

### Feat

- launch webserver as core boots
- allow --watch exec to run test on filesystem changes ([#49](https://github.com/PlaceOS/core/pull/49))

## v2.5.9 (2020-10-22)

### Feat

- add environment variable list behind `-e/--env`

## v2.5.8 (2020-09-24)

### Fix

- **module_manager**: `refresh_module` consistently returned false
- update logic modules on all system changes
- chomp build timestamp
- start/update control system logic modules on change

## v2.5.6 (2020-09-09)

### Feat

- **compilation**: serialize compilation

### Refactor

- remove reimport of Resource
- lazy getters

## v2.5.4 (2020-08-19)

### Feat

- **Dockerfile**: add commit level to logs
- **app**: add commit level and build time to logs
- **Dockerfile**: ensure certificates up to date

## v2.5.3 (2020-08-07)

### Refactor

- models refresh ([#41](https://github.com/PlaceOS/core/pull/41))

### Fix

- **resource**: retry changefeed

## v2.5.1 (2020-07-15)

### Fix

- update tasker
- **command controller**: don't double serialize JSON
- **command spec**: response is not double serialized
- **command controller**: don't double serialize JSON

## v2.4.0 (2020-07-02)

### Feat

- add secrets and clean up config

## v2.3.3 (2020-06-24)

### Fix

- fixed size error buffer
- **resource**: use same thread and avoid not_nil requirement
- hang on core load with > 64 resources
- nilable resource
- use `.all`
- hang on core load with > 64 resources
- **app controller**: requires a local logger
- **app controller**: requires a local logger
- **Log**: use `Log#setup`
- log setup on 0.35
- **Log**: use `Log#setup`

### Feat

- **resource**: log the resource loaded count

## v2.3.1 (2020-06-17)

## v2.3.0 (2020-06-15)

### Fix

- **module_manager**: convert to a Resource
- **module_manager**: restart iff node is responsible for module

### Refactor

- rename to `placeos-core`

## v1.2.7 (2020-05-14)

### Fix

- **client**: correct `terminate` path

## v1.2.6 (2020-05-13)

## v1.2.5 (2020-05-08)

## v1.2.4 (2020-05-04)

### Fix

- **resource**: handle Resource::Result::Error

## v1.2.3 (2020-05-01)

### Fix

- **resource**: handle Resource::Result::Error

## v1.2.2 (2020-05-01)

### Fix

- **resource:compilation**: use HEAD

## v1.2.1 (2020-04-30)

### Fix

- **resource:cloning**: ignore Interface Repositories

### Refactor

- **config**: set log level for all libraries through environment

## v1.2.0 (2020-04-23)

### Refactor

- migrate to Log

### Fix

- **client**: correct `load` path
- **config**: hounddog no longer needs a logger

## v1.1.4 (2020-04-20)

### Fix

- **client**: initialize for default response
- **client**: ensure connection closed

## v1.1.3 (2020-04-19)

### Fix

- **client**: correct path for driver status, have defaults in case of error

### Feat

- **client**: `#loaded` shows the modules on a driver

## v1.1.2 (2020-04-17)

### Fix

- **client**: correct typing of response objects

## v1.1.0 (2020-04-14)

### Fix

- **module_manager**: load modules on start up

### Feat

- **client**: add `load` and `driver_compiled?`

### Refactor

- move `load` from Api::Status to Api::Command

## v1.0.0 (2020-04-10)

### Fix

- user core master

## v0.1.0 (2020-04-06)

### Feat

- **resource:compilation**: react to forced recompile data events
- **resource:settings_update**: implement Module reloads on Settings changes
- **mappings:module_names**: resource event handler for module renames
- improve values returned from load
- **module manager**: optimise settings unescaping
- **status controller**: add loaded module introspection
- use environment variables to expose host details
- **client**: include host and port in errors
- **client.cr**: provide more context in error messages
- **Docker**: use alpine for smaller images
- add clustering module
- **core module manager**: implement module save setting request
- **core module manager**: add support for logic execute
- **client**: add method for obtaining driver metadata
- **drivers controller**: add route to obtain driver metadata
- **startup**: implement indirect module mapping management, refactor of Resource
- **controllers**: logging, default driver repository path
- **client**: better typing on exec method
- **module_manager**: load_module
- **logging**: use action-controller logger
- **startup:cloning**: update repository commit hash iff id maps to node or in startup
- **startup:compilation**: prevent multiple writers on driver commit
- handle 'head' logic in Cloning and Compilation
- **config**: update logging
- **startup:cloning**: pull if repository exists on startup
- **logging**: update to action-controller 2.0
- **client**: bindings for the core api
- **startup**: compilation specs, collect processed resources in Core::Resource
- **startup**: start ModuleManager
- **startup**: singleton resource manager
- **status**: add compilation and cloning errors
- **config**: configure service discovery from environment
- **startup**: moduleManager listens for Model::Module changes
- **startup**: module manager
- **startup**: compilation
- **startup**: cloning
- **api**: add drivers and chaos APIs

### Fix

- **resource:compilation**: set commit in `compile_driver`
- **controller:drivers**: correct Time::Span usage
- correctly load modules
- **controller:drivers**: fix name clash
- add driver id to compiled binaries
- **controller:drivers**: use `exit_code`
- **resource:cloning**: implement `rmdir_r` to recursively delete a directory
- **controller:status**: delete temporary driver binaries
- **resource:compilation**: reload modules if the binary exists
- **resource:cloning**: prioritise repository user/pass
- **module_manager**: start/stop modules
- **mappings**: ensure system indexes are updated
- **module_manager**: simplify payload generation
- **mappings.cr**: ignore empty name strings
- **mappings**: indexes were not being created properly
- **mappings**: refactor system lookup hash creation
- **compilation**: repository should use folder_name
- **status**: all types to be float64s
- **resource:mappings**: fire 'lookup-change' event when System Module ordering is set/updated
- **controller:status**: set NaNs to -1
- **spec:helper**: remove reference to removed `version` field of driver model
- **resource:mappings**: fix off by 1 error, and potential for misaligned keys in redis
- **client**: ensure route components are encoded
- **client.cr**: remove explicit return type
- **client.cr**: properly parse the commit response
- expose core host and core port seperately
- **resource:cloning**: set `@startup = true` in initializer
- segfault diagnosed and treated
- wip, tracing a segfault
- **constants**: improved version extraction
- **cloning**: should be using folder name
- remove exec_from target, correct setting of logger
- **Docker**: requires libssh2-dev
- **resource**: loop processing of resources, catch errors in fibers
- **spec:module_manager**: correct signature for ModuleManager
- **resource manager**: startup logging format
- **client**: rename driver_metadata to driver_details
- **core client**: driver file name needs to be URI encoded
- **core client**: URI#host can be nil
- **client**: hash#compact yields NoReturn type values
- **command controller**: remove contextual information on error
- **command controller**: error responses to contain more info
- **client**: correct captured block semantics
- **startup:mappings**: controlSystems processed on startup
- **resource_manager**: fix singleton instantiation
- **controllers**: hack around action-controller matching all prefixes for a controller
- **resource**: accumulate a fixed-sized buffer of processed resources
- **client**: engine -> ACAEngine
- top-level module naming, port type

### Perf

- **controller:details**: cache details requests

### Refactor

- **mappings:control_system_modules**: minor rewrite to use collection apis
- **resource:mappings**: factor out mapping creation
- `ACAEngine` -> `PlaceOS`, `engine-core` -> `core`
- move resource initialization to Core module method `start_managers`
- **module_manager**: use class based clustering, create mocked `Clustering` class
- use Application logger in ResourceManager
- **spawn**: set same_thread in anticipation of multi-threading support
- **compilation**: compilation as a class method
- **models**: use separated engine-models library
- Engine -> ACAEngine
