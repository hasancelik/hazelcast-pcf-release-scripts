from ruamel.yaml import YAML
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument("-v", "--release-version", dest="version")
parser.add_argument("-f", "--tile-file", dest="file")
args = parser.parse_args()

tile_file = args.file
release_version = args.version

yaml = YAML()
with open(tile_file) as file:
    tile = yaml.load(file)

for package in tile['packages']:
    if package['name'] == "hazelcast-boshrelease":
        package['path'] = "resources/hazelcast-boshrelease-" + release_version + ".tgz"
    if package['name'] == "on-demand-service-broker":
        for job in package['jobs']:
            if job['name'] == "broker":
               for release in job['properties']['service_deployment']['releases']:
                   if release['name'] == "hazelcast-boshrelease":
                       release['version'] = release_version

with open(tile_file, 'w') as file:
    yaml.dump(tile, file)