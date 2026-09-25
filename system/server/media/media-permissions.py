"""Keep the media library readable and writable by the shared `users` group.

Every service in this stack runs in one group and hands files along a chain:
the download client writes, an *arr application imports, a server presents.
That only works while every path under /Vault/Media is readable *and writable*
by the group, and while directories are setgid so whatever a service creates
keeps the group rather than the writer's own.

tmpfiles creates the top-level directories correctly, but nothing enforces it
on the files inside them, and the two ways it goes wrong are both silent until
something else fails:

  * a service that wrote while its primary group was something else (Jellyfin
    ran as `jellyfin:988` before it was moved into `users`) leaves files whose
    group no longer even exists;
  * a service writing under a umask of 0077 leaves them mode 0600.

Either way the next service in the chain is refused access, and the failure
surfaces as a message that reads like a bug in the *reader*:
"Access to the path '/Vault/Media/Shows/...' is denied".

This walks the library and repairs exactly what is wrong - nothing that is
already correct is touched - so a healthy run changes nothing and logs nothing.
It is cheap: the library is a few hundred directories and a few thousand files,
however many TiB of media those contain. The walk is over METADATA only.

Deliberate limits:

  * Only /Vault/Media, not /Vault/Downloads: the download staging area is
    transient, its contents are rewritten by the download client, and the *arr
    applications are given their own category directories there.
  * Only group bits are changed. Owner and other bits are left exactly as they
    are: who owns a file is the application's business, while whether the next
    service can read it is this script's.
  * Symlinks are never followed or modified; they are skipped entirely, since
    chmod on one silently changes its target.
"""

import grp
import os
import stat
import sys

ROOT = "/Vault/Media"
GROUP = "users"


def main(root=None):
    root = root or ROOT
    if not os.path.isdir(root):
        return 0

    try:
        gid = grp.getgrnam(GROUP).gr_gid
    except KeyError:
        print(f"media-permissions: no group {GROUP!r}", file=sys.stderr)
        return 1

    counts = {"regrouped": 0, "directories": 0, "files": 0}
    failures = 0

    for dirpath, dirnames, filenames in os.walk(root, onerror=lambda e: None):
        # Directories are repaired as they are visited; the walk still descends
        # into one whose mode it just fixed, because traversal is by path.
        for path, is_dir in [(dirpath, True)] + [
            (os.path.join(dirpath, name), False) for name in filenames
        ]:
            try:
                st = os.lstat(path)
            except OSError:
                continue

            # Skip anything that is not a plain file or directory - a symlink
            # included, because chmod would follow it and change the target.
            if is_dir and not stat.S_ISDIR(st.st_mode):
                continue
            if not is_dir and not stat.S_ISREG(st.st_mode):
                continue

            if st.st_gid != gid:
                try:
                    # -1 keeps the owner: only the group is this script's to set.
                    os.chown(path, -1, gid)
                    counts["regrouped"] += 1
                except OSError as error:
                    failures += 1
                    print(f"media-permissions: {path}: {error}", file=sys.stderr)
                    continue

            if is_dir:
                wanted = stat.S_IRGRP | stat.S_IWGRP | stat.S_IXGRP | stat.S_ISGID
                key = "directories"
            else:
                wanted = stat.S_IRGRP | stat.S_IWGRP
                key = "files"

            mode = stat.S_IMODE(st.st_mode)
            if (mode | wanted) == mode:
                continue
            try:
                os.chmod(path, mode | wanted)
                counts[key] += 1
            except OSError as error:
                failures += 1
                print(f"media-permissions: {path}: {error}", file=sys.stderr)

    changed = sum(counts.values())
    if changed:
        print(
            "media-permissions: repaired "
            f"{counts['regrouped']} path(s) not in group {GROUP}, "
            f"{counts['directories']} directories and {counts['files']} files"
        )
    if failures:
        print(f"media-permissions: {failures} path(s) could not be repaired", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    # The optional argument exists so the repair can be pointed at a copy of
    # the tree (or a test fixture) instead of the live library.
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else None))
