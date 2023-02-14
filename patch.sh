#!/bin/bash

set -e

SOURCE=$1
DEST=$2

git checkout master
git diff 274d1b3d32d90e7cdb1bfdba344256 HEAD -- $SOURCE > patch.diff
git checkout prefab2
patch --no-backup-if-mismatch --merge -p1 $DEST patch.diff
code -r $DEST