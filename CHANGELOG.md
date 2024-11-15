## v4.15.0 (2024-11-15)

### Feat

- **Dockerfile**: minimal core

## v4.14.7 (2024-11-14)

### Fix

- **Dockerfile**: owner user must exist on the filesystem

## v4.14.6 (2024-11-14)

### Fix

- **Dockerfile**: ensure tmp folder has the correct permissions ([#274](https://github.com/PlaceOS/core/pull/274))

## v4.14.5 (2024-08-17)

### Fix

- **Dockerfile**: edge tmp folder permissions

## v4.14.4 (2024-05-24)

### Fix

- **shard.lock**: ConnectProxy::HTTPClient class methods ignore proxy

## v4.14.3 (2024-05-24)

### Fix

- **driver_manager**: should be truncating when recomp driver is retrieved ([#273](https://github.com/PlaceOS/core/pull/273))

## v4.14.2 (2024-05-13)

### Fix

- **logging**: PPT-1368 - logging to use placeos-log-backend ([#271](https://github.com/PlaceOS/core/pull/271))

## v4.14.1 (2024-04-12)

### Fix

- **shard.yml**: specify driver version

## v4.14.0 (2024-04-12)

### Feat

- migrate to redis for service discovery ([#268](https://github.com/PlaceOS/core/pull/268))

## v4.13.1 (2024-03-19)

### Fix

- **driver_manager**: interacting with private repo ([#267](https://github.com/PlaceOS/core/pull/267))

## v4.13.0 (2024-03-19)

### Feat

- integrate build service ([#266](https://github.com/PlaceOS/core/pull/266))

## v4.11.10 (2023-10-04)

### Fix

- **healthcheck**: usename can be null causing errors

## v4.11.9 (2023-07-24)

### Fix

- **module_manager**: update to a lazy model loading method

## v4.11.8 (2023-07-14)

### Fix

- **resource**: replaced change feed iterator with async closure

## v4.11.7 (2023-07-14)

### Fix

- **resource**: replaced change feed iterator with async closure

## v4.11.6 (2023-07-14)

### Fix

- **local**: error message may not be present

## v4.11.5 (2023-07-14)

### Fix

- **resource**: missing change events

## v4.11.4 (2023-07-11)

### Fix

- **module_manager**: treat load as a stabilization event

## v4.11.3 (2023-07-04)

### Fix

- **eventbus**: handle read replica race conditions

## v4.11.2 (2023-07-04)

### Fix

- **eventbus**: handle read replica race conditions

## v4.11.1 (2023-06-27)

### Fix

- **process_check**: kill unresponsive processes cleanly ([#263](https://github.com/PlaceOS/core/pull/263))

## v4.11.0 (2023-06-26)

### Feat

- **shard.lock**: bump opentelemetry-instrumentation.cr

## v4.10.0 (2023-05-04)

### Feat

- **edge/protocol**: add support for crystal 1.8 ([#260](https://github.com/PlaceOS/core/pull/260))

## v4.9.5 (2023-03-15)

### Refactor

- migrate to postgres ([#248](https://github.com/PlaceOS/core/pull/248))

## v4.9.4 (2023-03-15)

### Fix

- **process_check**: resolve possible hang condition

## v4.9.3 (2023-03-14)

### Fix

- **process_check**: ensure consistent state after recovery ([#259](https://github.com/PlaceOS/core/pull/259))

## v4.9.2 (2023-02-23)

### Fix

- **process_manager/common**: prevent potential for deadlock ([#257](https://github.com/PlaceOS/core/pull/257))

## v4.9.1 (2023-02-22)

### Fix

- **process_manager**: don't lock managers when querying ([#256](https://github.com/PlaceOS/core/pull/256))

## v4.9.0 (2023-02-06)

### Feat

- improve cluster stabilisation under adverse conditions ([#254](https://github.com/PlaceOS/core/pull/254))

## v4.8.4 (2023-01-09)

### Fix

- **edge/transport**: restart service after a period of downtime ([#253](https://github.com/PlaceOS/core/pull/253))

## v4.8.3 (2022-12-23)

### Fix

- **edge/transport**: possible reconnection issue ([#251](https://github.com/PlaceOS/core/pull/251))

## v4.8.2 (2022-12-19)

### Fix

- **process_manager/local**: add edge node awareness ([#250](https://github.com/PlaceOS/core/pull/250))

## v4.8.1 (2022-12-09)

### Fix

- **api/drivers**: allow branch selection ([#249](https://github.com/PlaceOS/core/pull/249))

## v4.8.0 (2022-11-23)

### Feat

- **edge**: improve driver launch reliability ([#247](https://github.com/PlaceOS/core/pull/247))

## v4.7.1 (2022-11-02)

### Fix

- **Dockerfile**: use `placeos/crystal` base images

## v4.7.0 (2022-10-01)

### Feat

- **edge/protocol**: start modules as part of the handshake ([#240](https://github.com/PlaceOS/core/pull/240))

## v4.6.5 (2022-09-30)

### Fix

- **manager/edge**: start modules after registration ([#238](https://github.com/PlaceOS/core/pull/238))

## v4.6.4 (2022-09-29)

### Fix

- **edge/transport**: ensure reconnect is not missed ([#237](https://github.com/PlaceOS/core/pull/237))

## v4.6.3 (2022-09-14)

### Fix

- **Dockerfile**: requires make

## v4.6.2 (2022-09-14)

### Fix

- **Dockerfile**: ensure exec_from included in release

## v4.6.1 (2022-09-13)

### Fix

- **edge/transport**: reconnect on graceful api disconnect ([#234](https://github.com/PlaceOS/core/pull/234))

## v4.6.0 (2022-09-08)

### Feat

- **Dockerfile**: revert static build ([#233](https://github.com/PlaceOS/core/pull/233))

## v4.5.0 (2022-09-07)

### Feat

- update action controller and support ARM64 ([#232](https://github.com/PlaceOS/core/pull/232))

## v4.4.3 (2022-08-15)

### Fix

- handle driver `module_name` changes in module mappings ([#230](https://github.com/PlaceOS/core/pull/230))

### Refactor

- **api/command**: extract attaching debugger ([#224](https://github.com/PlaceOS/core/pull/224))

## v4.4.2 (2022-08-11)

### Fix

- remove Dead state
- **process_check**: use `reject!`

### Refactor

- use Tasker instead of Timeout shard ([#229](https://github.com/PlaceOS/core/pull/229))

## v4.4.1 (2022-07-26)

### Fix

- **process_check**: fix a race condition ([#226](https://github.com/PlaceOS/core/pull/226))

## v4.4.0 (2022-07-22)

### Feat

- **module_manager**: periodically check that processes are alive ([#225](https://github.com/PlaceOS/core/pull/225))

## v4.3.2 (2022-07-20)

### Fix

- **control_system_modules**: ensure correct totals when refreshing ([#222](https://github.com/PlaceOS/core/pull/222))
- **control_system_modules**: update system references in modules ([#215](https://github.com/PlaceOS/core/pull/215))

## v4.3.1 (2022-05-25)

### Fix

- **edge**: use correct api-key param and update key validation  ([#181](https://github.com/PlaceOS/core/pull/181))

## v4.3.0 (2022-05-16)

### Feat

- **cloning**: use deployed_commit_hash to indicate current commit ([#179](https://github.com/PlaceOS/core/pull/179))

## v4.2.4 (2022-05-04)

### Fix

- **edge**: resolve `crystal not found` error ([#178](https://github.com/PlaceOS/core/pull/178))

## v4.2.3 (2022-05-03)

### Fix

- **telemetry**: ensure `Instrument` in scope

## v4.2.2 (2022-05-03)

### Fix

- update `placeos-log-backend`

## v4.2.1 (2022-04-28)

### Fix

- **telemetry**: seperate telemetry file

## v4.2.0 (2022-04-27)

### Feat

- **logging**: configure OpenTelemetry

## v4.1.0 (2022-04-26)

### Feat

- **logging**: add configuration by LOG_LEVEL env var

## v4.0.8 (2022-04-06)

### Fix

- **process_manager/common**: should propagate RemoteExceptions ([#175](https://github.com/PlaceOS/core/pull/175))

## v4.0.7 (2022-03-28)

### Fix

- **api**: add error codes to coming from RemoteExceptions ([#172](https://github.com/PlaceOS/core/pull/172))

## v4.0.6 (2022-03-21)

### Fix

- possible race condition in spawn ([#171](https://github.com/PlaceOS/core/pull/171))

## v4.0.5 (2022-03-03)

### Fix

- **edge**: update require

## v4.0.4 (2022-03-03)

### Refactor

- **module_manager**: move process manager lookup by path to ModuleManager
- use `Log.with_context` with args

## v4.0.3 (2022-03-03)

### Refactor

- **module_manager**: remove `ext`, `require "uri/json"`

## v4.0.2 (2022-03-02)

### Fix

- better module stopped errors ([#163](https://github.com/PlaceOS/core/pull/163))

## v4.0.1 (2022-03-01)

### Fix

- CVE-2022-23990 and CVE-2022-23852

## v4.0.0 (2022-02-24)

### Feat

- add support for custom response codes ([#161](https://github.com/PlaceOS/core/pull/161))
- **api/command**: propagate `user_id` ([#153](https://github.com/PlaceOS/core/pull/153))
- **drivers**: persist driver bins and repos across container recreation ([#142](https://github.com/PlaceOS/core/pull/142))

### Fix

- **api command**: ensure debug writes are serialised ([#146](https://github.com/PlaceOS/core/pull/146))
- **api command**: obtain latest process manager to ignore ([#144](https://github.com/PlaceOS/core/pull/144))
- **edge**: handle proxied PUBLISH events
- **api:drivers**: account for branch in commit listing
- bump placeos-compiler
- **process_manager/local**: reduce severity of missing mod manager log
- driver compilation from non-default branches
- **resource:cloning**: decrypt password on use

### Refactor

- **edge/client**: update secret, remove `edge_id` ([#162](https://github.com/PlaceOS/core/pull/162))
- central build ci ([#159](https://github.com/PlaceOS/core/pull/159))
- **process_manager**: load errors messages ([#154](https://github.com/PlaceOS/core/pull/154))

## v3.11.0 (2021-07-29)

### Feat

- **client**: add debug method returning websocket ([#119](https://github.com/PlaceOS/core/pull/119))

### Refactor

- **client**: improve client for use with driver ([#118](https://github.com/PlaceOS/core/pull/118))

## v3.10.6 (2021-07-20)

### Fix

- **core client**: wait for response to complete

## v3.10.5 (2021-07-20)

### Feat

- **shard.yml**: bump version

### Fix

- **core client**: ensure body has completely downloaded

## v3.10.3 (2021-07-19)

### Fix

- **client/core**: allow empty initializer for DriverStatus

## v3.10.1 (2021-07-09)

### Feat

- embed curl in CLI

### Fix

- **module_manager**: pass repository to compiled check
- **Dockerfile**: add yaml-static

### Refactor

- move controllers to an api folder
- **client**: tidy up
- clean up Log contexts
- **managers**: less noise in handlers

## v3.10.0 (2021-06-28)

### Feat

- **core/client:branches**: add branches to client
- **controller/drivers**: add branch listing

### Fix

- **logging**: set progname

### Refactor

- remove a set of NamedTuples from code base
- **controller/drivers**: use a more explicit id param
- **config**: extract logging to logging.cr

## v3.8.1 (2021-04-26)

### Feat

- support branch switching
- **controllers:command**: trace log when adding a debug session
- add verbose signalling
- add cause to raised Resource::ProcessingError
- **controller:root**: better healthcheck
- **resource:compilation**: add failed compilation output to the driver

### Fix

- **settings_update**: ensure non-erroring settings updates complete
- drop excess libssh2 libs
- **logging**: fix logstash logging, ensure consistent logs at startup

### Refactor

- **spec**: stop using a global ResourceManager instance
- **root**: pull readiness check out of controller

### Perf

- **module_manager**: allocate an array of batch size
- **module_manager**: parallel load of modules during stabilization

## v3.4.0 (2021-03-08)

### Fix

- **module_manager**: prevent multiple stabilisations via lock

### Refactor

- use driver binary name rather than path

## v3.3.0 (2021-02-25)

### Feat

- **process_manager**: add system_model callback

### Fix

- **config**: report logs in milliseconds only

### Refactor

- use placeos log backend

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

### Feat

- launch webserver as core boots
- allow --watch exec to run test on filesystem changes ([#49](https://github.com/PlaceOS/core/pull/49))

### Fix

- ensure module manager starts in resource manager callback
- **test**: remove container names from docker-compose
- **log**: bind to correct log namespace

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

### Fix

- **resource**: retry changefeed

### Refactor

- models refresh ([#41](https://github.com/PlaceOS/core/pull/41))

## v2.5.1 (2020-07-15)

### Fix

- update tasker
- **command spec**: response is not double serialized
- **command controller**: don't double serialize JSON

## v2.4.0 (2020-07-02)

### Feat

- add secrets and clean up config

## v2.3.3 (2020-06-24)

### Feat

- **resource**: log the resource loaded count

### Fix

- fixed size error buffer
- **resource**: use same thread and avoid not_nil requirement
- nilable resource
- use `.all`
- hang on core load with > 64 resources
- **app controller**: requires a local logger
- **app controller**: requires a local logger
- log setup on 0.35
- **Log**: use `Log#setup`

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

### Fix

- **client**: correct `load` path
- **config**: hounddog no longer needs a logger

### Refactor

- migrate to Log

## v1.1.4 (2020-04-20)

### Fix

- **client**: initialize for default response
- **client**: ensure connection closed

## v1.1.3 (2020-04-19)

### Feat

- **client**: `#loaded` shows the modules on a driver

### Fix

- **client**: correct path for driver status, have defaults in case of error

## v1.1.2 (2020-04-17)

### Fix

- **client**: correct typing of response objects

## v1.1.0 (2020-04-14)

### Feat

- **client**: add `load` and `driver_compiled?`

### Fix

- **module_manager**: load modules on start up

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
- **Docker**: requires libssh2-dev
- remove exec_from target, correct setting of logger
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

### Perf

- **controller:details**: cache details requests
