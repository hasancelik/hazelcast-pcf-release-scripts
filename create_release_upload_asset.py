from github import Github
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument("-t", "--github-token", dest="token")
parser.add_argument("-r", "--github-repo", dest="repo")
parser.add_argument("-v", "--release-version", dest="version")
parser.add_argument("-hzv", "--hazelcast-version", dest="hzVersion")
parser.add_argument("-a", "--release-asset-path", dest="asset")
args = parser.parse_args()

releaseVersion = args.version
hazelcastVersion = args.hzVersion
assetPath = args.asset

g = Github(args.token)
repo = g.get_repo(args.repo)

releaseTag="v" + releaseVersion
releaseMessage = "Upgraded hazelcast and mancenter to " + hazelcastVersion + " for " + releaseVersion + " release"

repo.create_git_release(releaseTag, releaseVersion, releaseMessage)
release = repo.get_release(releaseTag)
release.upload_asset(assetPath)