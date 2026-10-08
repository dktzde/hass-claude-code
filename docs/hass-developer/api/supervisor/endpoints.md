For API endpoints marked with :lock: you need use an authorization header with a `Bearer` token.

The token is available for apps (formerly known as add-ons) and Home Assistant using the
`SUPERVISOR_TOKEN` environment variable.

To see more details about each endpoint, click on it to expand it.

### Apps

### Audio

### Auth

### Backup

### CLI

### Core

### Discovery

### DNS

### Docker

### Hardware

### Host

### Ingress

### Jobs

### Root

### Mounts

### Multicast

### Network

### Observer

### OS

### Resolution

### Service

### Store

### Security

### Supervisor

### Time

### Placeholders

Some of the endpoints uses placeholders indicated with `<...>` in the endpoint URL.

| placeholder | description                                                                                                                                           |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| app         | The slug for the app, to get the slug you can call `/addons`, to call endpoints for the app calling the endpoints you can use `self` as the slug. |
| application | The name of an application, call `/audio/info` to get the correct name                                                                                |
| backup      | A valid backup slug, example `skuwe823`, to get the slug you can call `/backups`                                                                      |
| bootid      | An id or offset of a particular boot, used to filter logs. Call `/host/logs/boots` to get a list of boot ids or see `/host/logs/boots/<bootid>` to understand boot offsets |
| check       | The slug of a system check in Supervisor's resolution manager. Call `/resolution/info` for a list of options from the `checks` field                  |
| disk        | Identifier of a disk attached to host or `default`. See `/host/disks/<disk>/usage` for more details                                                   |
| id          | Numeric id of a vlan on a particular interface. See `/network/interface/<interface>/vlan/<id>` for details                                            |
| identifier  | A syslog identifier used to filter logs. Call `/host/logs/identifiers` to get a list of options. See `/host/logs/identifiers/<identifier>` for some common examples |
| interface   | A valid interface name, example `eth0`, to get the interface name you can call `/network/info`. You can use `default` to get the primary interface    |
| issue       | The UUID of an issue with the system identified by Supervisor. Call `/resolution/info` for a list of options from the `issues` field                  |
| job_id      | The UUID of a currently running or completed Supervisor job                                                                                           |
| name        | Name of a mount added to Supervisor. Call `/mounts` to get a list of options from `mounts` field                                                      |
| registry    | A registry hostname defined in the container registry configuration, to get the hostname you can call `/docker/registries`                            |
| repository  | The slug of an app repository added to Supervisor. Call `/store` for a list of options from the `repositories` field                                |
| service     | The service name for a service on the host.                                                                                                           |
| suggestion  | The UUID of a suggestion for a system issue identified by Supervisor. Call `/resolution/info` for a list of options from the `suggestions` field      |
| uuid        | The UUID of a discovery service, to get the UUID you can call `/discovery`                                                                            |
