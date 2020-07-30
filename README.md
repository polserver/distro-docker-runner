# polserver-runner

Docker image to spawn a PenUltima Online server.

This image is primarily used for testing, and as such performance has **NOT**
been vetted. Use in production at your own risk.

## Settings

These _optional_ environmental variables may be used when spawning the container to configure the runner:

| Variable | Description | Default |
|----------|-------------|---------|
| POLSERVER_UODATADIR | Location of client data files. Client data files must be available if realm data is not present in `POLSERVER_REALMDIR` (see below). | /MUL |
| POLSERVER_SHARDDIR | Location to unzip data. If this is a mounted volume, _all shard data_ will persist across container runs. It is **not recommended* to mount the Shard directory, as read-writes between host OS and docker containers are a heavy bottleneck in performance. | /Shard |
| POLSERVER_REALMDIR | Location to store converted realm data. If this is a mounted volume, realm generation will be persisted across container runs.| /Realm |
| POLSERVER_DISTROZIP | The URL of distro zip. Can use a `file://` URI for locally available ZIPs in the container. | https://github.com/polserver/ModernDistro/archive/master.zip |
| POLSERVER_COREZIP | The URL of polserver release zip. Can use a `file://` URI for locally available ZIPs in the container.| https://github.com/polserver/polserver/releases/download/NightlyRelease/Nightly-Linux-gcc.zip |

## Prerequisites

The following client files are needed in the `POLSERVER_UODATADIR` for
`uoconvert` to run if realms are not present in `POLSERVER_REALMDIR`:
- map?.mul
- mapdif?.mul
- mapdifl?.mul
- multi.idx
- multi.mul
- stadif?.mul
- stadifi?.mul
- stadifl?.mul
- staidx?.mul
- statics?.mul
- tiledata.mul
- verdata.mul

## Known limitations

- The port must be 5003.
- Cannot easily copy an existing unzipped test directory of a core or distro.
- Server will not reboot/restart on crash; it is one-shot.

## Examples

### Windows (PowerShell)

```sh
# Build the image
docker build -t polserver-runner .

# Run the image...
# - in a container named `polserver`
# - with an interactive shell (-it)
# - that deletes on shutdown (--rm)
# - that persists shard data files to Host OS in .\Shard\data
# - that persists realm data to Host OS in .\Realm
# - that uses the official default install location for client files if uoconvert must be ran
docker run --name polserver -it --rm  -v ${PWD}\Shard\data:/Shard/data -v ${PWD}\Realm:/Realm -v "C:\Program Files (x86)\Electronic Arts\Ultima Online Classic:/MUL" polserver-runner

# When the container is actively running, connect a new bash terminal:
docker exec -it polserver /bin/bash
```
