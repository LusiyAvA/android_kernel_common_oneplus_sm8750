#!/usr/bin/env python3
# Luna content-level three-way merge of an ACK release into this tree.
#
# Why not `git merge`: the OnePlus GitHub history does not share commit
# ancestry with android.googlesource.com/kernel/common, so git picks a
# bogus ancient merge base and reports hundreds of false conflicts.
# Content-wise the base of this tree is exactly ACK
# android15-6.6-2026-01_r22, so a file-level three-way merge against
# that tree is equivalent to a clean git merge:
#
#   ours == base            -> take theirs (ACK update)
#   theirs == base          -> keep ours (OnePlus change)
#   ours == theirs          -> keep
#   both changed            -> git merge-file; on conflict, use a
#                                pre-resolved file (or a patch carrying an
#                                explicit keep-ours directive) from
#                                patches/ack-merge-resolved/<path>
#                                if present, else fail listing it.
#
# Usage: luna-ack-merge.py --base DIR --theirs DIR [--ours DIR]
#                          [--resolved DIR]
import argparse, hashlib, os, shutil, subprocess, sys

def scan(root):
    """relpath -> (kind, digest) where kind is 'file' or 'link'."""
    out = {}
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d != ".git"]
        for name in fn:
            p = os.path.join(dp, name)
            rel = os.path.relpath(p, root)
            if os.path.islink(p):
                out[rel] = ("link", os.readlink(p))
            else:
                h = hashlib.sha1()
                with open(p, "rb") as fh:
                    for chunk in iter(lambda: fh.read(1 << 20), b""):
                        h.update(chunk)
                out[rel] = ("file", h.hexdigest())
    return out

def materialize(src_root, rel, dst_root):
    src = os.path.join(src_root, rel)
    dst = os.path.join(dst_root, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.islink(dst) or os.path.exists(dst):
        os.remove(dst)
    if os.path.islink(src):
        os.symlink(os.readlink(src), dst)
    else:
        shutil.copy2(src, dst)

def remove_path(root, rel):
    p = os.path.join(root, rel)
    if os.path.islink(p) or os.path.exists(p):
        os.remove(p)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--theirs", required=True)
    ap.add_argument("--ours", default=".")
    ap.add_argument("--resolved", default="patches/ack-merge-resolved")
    a = ap.parse_args()

    base, theirs, ours = scan(a.base), scan(a.theirs), scan(a.ours)
    keys = set(base) | set(theirs) | set(ours)
    conflicts, stats = [], {"theirs": 0, "ours": 0, "merged": 0,
                            "resolved": 0, "deleted": 0, "added": 0}

    for rel in sorted(keys):
        b, t, o = base.get(rel), theirs.get(rel), ours.get(rel)
        if o == t:
            continue                      # identical (or both absent)
        if o == b:                        # only ACK changed/added/deleted
            if t is None:
                remove_path(a.ours, rel); stats["deleted"] += 1
            else:
                materialize(a.theirs, rel, a.ours)
                stats["theirs" if b else "added"] += 1
            continue
        if t == b:                        # only we changed/added/deleted
            stats["ours"] += 1
            continue
        # Both sides changed (or conflicting add/delete).
        resolved = os.path.join(a.resolved, rel)
        if (b and t and o and b[0] == t[0] == o[0] == "file"):
            tmp = "/tmp/luna-merge-out"
            r = subprocess.run(
                ["git", "merge-file", "-p",
                 os.path.join(a.ours, rel), os.path.join(a.base, rel),
                 os.path.join(a.theirs, rel)],
                capture_output=True)
            if r.returncode == 0:
                with open(os.path.join(a.ours, rel), "wb") as fh:
                    fh.write(r.stdout)
                stats["merged"] += 1
                continue
        if os.path.isfile(resolved):
            dst = os.path.join(a.ours, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if os.path.islink(dst) or os.path.exists(dst):
                os.remove(dst)
            shutil.copy2(resolved, dst)
            stats["resolved"] += 1
            continue
        patch = resolved + ".patch"
        if os.path.isfile(patch):
            with open(patch, "rb") as fh:
                if fh.readline().strip() == b"# luna-ack-merge: keep-ours":
                    stats["resolved"] += 1
                    continue
            # Patch form (for very large files): a unified diff from
            # the stock (ours) file to the hand-resolved merged file.
            r = subprocess.run(["git", "apply",
                                os.path.abspath(patch)],
                               cwd=a.ours, capture_output=True)
            if r.returncode == 0:
                stats["resolved"] += 1
                continue
        conflicts.append(rel)

    print(f"[luna-ack-merge] took ACK version: {stats['theirs']}, "
          f"ACK-added: {stats['added']}, ACK-deleted: {stats['deleted']}, "
          f"kept ours: {stats['ours']}, clean 3-way merges: {stats['merged']}, "
          f"pre-resolved: {stats['resolved']}")
    if conflicts:
        print("[luna-ack-merge] UNRESOLVED CONFLICTS:")
        for c in conflicts:
            print("  " + c)
        return 1
    print("[luna-ack-merge] done, no unresolved conflicts")
    return 0

if __name__ == "__main__":
    sys.exit(main())
#!/usr/bin/env python3
# Luna content-level three-way merge of an ACK release into this tree.
#
# Why not `git merge`: the OnePlus GitHub history does not share commit
# ancestry with android.googlesource.com/kernel/common, so git picks a
# bogus ancient merge base and reports hundreds of false conflicts.
# Content-wise the base of this tree is exactly ACK
# android15-6.6-2026-01_r22, so a file-level three-way merge against
# that tree is equivalent to a clean git merge:
#
#   ours == base            -> take theirs (ACK update)
#   theirs == base          -> keep ours (OnePlus change)
#   ours == theirs          -> keep
#   both changed            -> git merge-file; on conflict, use a
#                                pre-resolved file from
#                                patches/ack-merge-resolved/<path>
#                                if present, else fail listing it.
#
# Usage: luna-ack-merge.py --base DIR --theirs DIR [--ours DIR]
#                          [--resolved DIR]
import argparse, hashlib, os, shutil, subprocess, sys

def scan(root):
    """relpath -> (kind, digest) where kind is 'file' or 'link'."""
    out = {}
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d != ".git"]
        for name in fn:
            p = os.path.join(dp, name)
            rel = os.path.relpath(p, root)
            if os.path.islink(p):
                out[rel] = ("link", os.readlink(p))
            else:
                h = hashlib.sha1()
                with open(p, "rb") as fh:
                    for chunk in iter(lambda: fh.read(1 << 20), b""):
                        h.update(chunk)
                out[rel] = ("file", h.hexdigest())
    return out

def materialize(src_root, rel, dst_root):
    src = os.path.join(src_root, rel)
    dst = os.path.join(dst_root, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.islink(dst) or os.path.exists(dst):
        os.remove(dst)
    if os.path.islink(src):
        os.symlink(os.readlink(src), dst)
    else:
        shutil.copy2(src, dst)

def remove_path(root, rel):
    p = os.path.join(root, rel)
    if os.path.islink(p) or os.path.exists(p):
        os.remove(p)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--theirs", required=True)
    ap.add_argument("--ours", default=".")
    ap.add_argument("--resolved", default="patches/ack-merge-resolved")
    a = ap.parse_args()

    base, theirs, ours = scan(a.base), scan(a.theirs), scan(a.ours)
    keys = set(base) | set(theirs) | set(ours)
    conflicts, stats = [], {"theirs": 0, "ours": 0, "merged": 0,
                            "resolved": 0, "deleted": 0, "added": 0}

    for rel in sorted(keys):
        b, t, o = base.get(rel), theirs.get(rel), ours.get(rel)
        if o == t:
            continue                      # identical (or both absent)
        if o == b:                        # only ACK changed/added/deleted
            if t is None:
                remove_path(a.ours, rel); stats["deleted"] += 1
            else:
                materialize(a.theirs, rel, a.ours)
                stats["theirs" if b else "added"] += 1
            continue
        if t == b:                        # only we changed/added/deleted
            stats["ours"] += 1
            continue
        # Both sides changed (or conflicting add/delete).
        resolved = os.path.join(a.resolved, rel)
        if (b and t and o and b[0] == t[0] == o[0] == "file"):
            tmp = "/tmp/luna-merge-out"
            r = subprocess.run(
                ["git", "merge-file", "-p",
                 os.path.join(a.ours, rel), os.path.join(a.base, rel),
                 os.path.join(a.theirs, rel)],
                capture_output=True)
            if r.returncode == 0:
                with open(os.path.join(a.ours, rel), "wb") as fh:
                    fh.write(r.stdout)
                stats["merged"] += 1
                continue
        if os.path.isfile(resolved):
            dst = os.path.join(a.ours, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if os.path.islink(dst) or os.path.exists(dst):
                os.remove(dst)
            shutil.copy2(resolved, dst)
            stats["resolved"] += 1
            continue
        patch = resolved + ".patch"
        if os.path.isfile(patch):
            # Patch form (for very large files): a unified diff from
            # the stock (ours) file to the hand-resolved merged file.
            r = subprocess.run(["git", "apply",
                                os.path.abspath(patch)],
                               cwd=a.ours, capture_output=True)
            if r.returncode == 0:
                stats["resolved"] += 1
                continue
        conflicts.append(rel)

    print(f"[luna-ack-merge] took ACK version: {stats['theirs']}, "
          f"ACK-added: {stats['added']}, ACK-deleted: {stats['deleted']}, "
          f"kept ours: {stats['ours']}, clean 3-way merges: {stats['merged']}, "
          f"pre-resolved: {stats['resolved']}")
    if conflicts:
        print("[luna-ack-merge] UNRESOLVED CONFLICTS:")
        for c in conflicts:
            print("  " + c)
        return 1
    print("[luna-ack-merge] done, no unresolved conflicts")
    return 0

if __name__ == "__main__":
    sys.exit(main())
