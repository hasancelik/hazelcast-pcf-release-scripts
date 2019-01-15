from ruamel.yaml import YAML
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument("-f", "--blobs-file", dest="file")
args = parser.parse_args()

blobs_file = args.file

yaml = YAML()
with open(blobs_file) as file:
    blobs = yaml.load(file)

for blob in blobs:
    if "hazelcast-enterprise" in blob:
        del blobs[blob]
        break

for blob in blobs:
    if "mancenter" in blob:
        del blobs[blob]
        break

with open(blobs_file, 'w') as file:
    yaml.dump(blobs, file)