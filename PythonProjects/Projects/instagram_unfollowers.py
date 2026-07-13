import json
from pathlib import Path

# Get your data export from Instagram first:
# Settings > Accounts Center > Your information and permissions
# > Download your information > select JSON format > request for "Followers and following"
# Unzip the export and point these paths at the resulting files.
path = Path("C:\\Users\\prana\\Projects-\\Projects-\\PythonProjects\\connections\\followers_and_following")
FOLLOWERS_FILE = path / "followers_1.json"
FOLLOWING_FILE = path / "following.json"


def extract_usernames(data):
    # Instagram nests usernames inside string_list_data entries, but
    # following.json omits "value" and puts the username in the entry's "title" instead
    usernames = set()
    for entry in data:
        for item in entry.get("string_list_data", []):
            usernames.add(item.get("value") or entry.get("title"))
    return usernames


def load_followers(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return extract_usernames(data)


def load_following(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    # "following.json" wraps the list under this key instead of being a bare list
    return extract_usernames(data["relationships_following"])


followers = load_followers(FOLLOWERS_FILE)
following = load_following(FOLLOWING_FILE)

# People you follow who don't follow you back
not_following_back = sorted(following - followers)

print(f"Followers: {len(followers)}")
print(f"Following: {len(following)}")
print(f"\nAccounts you follow that don't follow you back ({len(not_following_back)}):")

for username in not_following_back:
    print(f"  - {username}")
