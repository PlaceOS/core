# Contributing

[PlaceOS](https://place.technology/) adheres to the [Contributor Covenent Code of Conduct](./CODE_OF_CONDUCT.md).

## Making Changes

### Pull Request Flow

- Open a pull request with your changes
- Ensure the PR title is in the form of a conventional commit (see below)
- Get CI to pass
- Request a review from someone who has worked on the codebase

### Commit Style

[PlaceOS](https://place.technology/) uses [conventional commits](https://www.conventionalcommits.org/en/v1.0.0/).


## Testing

Given you have the following dependencies...

- [docker](https://www.docker.com/)
- [docker-compose](https://github.com/docker/compose)

It is simple to develop the service with docker.

### With Docker

- Run specs, tearing down the `docker-compoe` environment upon completion.

```shell-session
$ ./test
```

- Run specs on changes to Crystal files within the `src` and `spec` folders.

```shell-session
$ ./test --watch
```

### Without Docker

- To run tests

```shell-session
$ crystal spec
```

**NOTE:** The upstream dependencies specified in `docker-compose.yml` are required...

## Compiling

```shell-session
$ shards build
```
