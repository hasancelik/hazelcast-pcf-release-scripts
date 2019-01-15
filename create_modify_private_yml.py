from ruamel.yaml import YAML
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument("-o", "--output-private-file", dest="output")
parser.add_argument("-a", "--access-key-id", dest="id")
parser.add_argument("-s", "--secret-key", dest="key")
args = parser.parse_args()

output_file = args.output
id = args.id
key = args.key

private_structure = """\
---
blobstore:
    options:
        access_key_id:
        secret_access_key:
"""

yaml = YAML()
private_yml = yaml.load(private_structure)
private_yml['blobstore']['options']['access_key_id'] = id
private_yml['blobstore']['options']['secret_access_key'] = key

with open(output_file, 'w') as output:
    yaml.dump(private_yml, output)