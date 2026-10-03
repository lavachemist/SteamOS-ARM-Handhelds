# gamescope

PB-OS's gamescope lives in its fork,
**https://github.com/project-barry/gamescope**, branch `dual-screen`:
upstream gamescope, then MaSi's Qualcomm (MSM) port as PB-OS runs it (one
"pb-os base" commit), then the dual-screen work (the AYN Thor's bottom
screen) as separate commits that other distributions can take on their own.
See DUAL-SCREEN.md there.

`REF` is the commit images build: `scripts/build-gamescope-in-rootfs.sh`
fetches it (with its submodules) and builds it inside the Frame rootfs.

Changing gamescope:

1. Commit and push to the fork's `dual-screen` branch.
2. Try it: `GAMESCOPE_REF=dual-screen` builds the branch's tip, or
   `GAMESCOPE_LOCAL=/path/to/checkout` a local checkout as it is.
3. Put the new commit in `REF` and commit that here.
