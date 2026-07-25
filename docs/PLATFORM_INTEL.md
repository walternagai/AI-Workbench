# Intel Platform Notes

Referenced by `platforms/intel/npu.sh` and `platforms/intel/oneapi.sh` when
their automated, best-effort install steps can't proceed on the current
system. Both paths are intentionally non-fatal (see docs/PRINCIPLES.md §1):
a missing NPU or oneAPI repo never aborts the overall install, since Vulkan
(llama.cpp) is the primary, always-available acceleration path on Intel
iGPUs/Arc — see docs/PRINCIPLES.md §4.

## NPU driver

Intel does **not** publish an apt repository for the NPU driver. Releases
are published as a single tarball per supported Ubuntu release at
[intel/linux-npu-driver](https://github.com/intel/linux-npu-driver/releases),
e.g. `linux-npu-driver-vX.Y.Z-...-ubuntu2404.tar.gz` — one tarball, one
Ubuntu version, no separate package per architecture/flavor.

`platforms/intel/npu.sh` looks for an asset matching
`ubuntu<VERSION_ID with dots removed>` (e.g. `ubuntu2404` for Ubuntu 24.04)
in the *latest* upstream release. If Intel hasn't published a matching
asset yet for your Ubuntu release — or you're on Pop!_OS/Linux Mint, whose
version numbers don't line up with Intel's Ubuntu-only asset names — the
script logs a warning and continues without NPU acceleration.

To install manually once a matching release exists:

```bash
sudo apt-get install -y libtbb12
curl -fsSL -o npu-driver.tar.gz <asset URL from the releases page>
mkdir npu-driver && tar -xzf npu-driver.tar.gz -C npu-driver
sudo dpkg -i npu-driver/*.deb   # excludes *.ddeb (debug) and *.asc (signatures)
```

## oneAPI runtime

Unlike the NPU driver, oneAPI redistributable runtime libraries **are**
served over an apt repository. `platforms/intel/oneapi.sh` only installs
them if that repo is already configured (checked via `apt-cache search`);
it does not add the repo itself, since a full oneAPI toolkit is heavyweight
and unnecessary for this stack's Vulkan-based inference path. To add it
manually:

```bash
wget -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
    | gpg --dearmor | sudo tee /usr/share/keyrings/oneapi-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
    | sudo tee /etc/apt/sources.list.d/oneAPI.list
sudo apt-get update
sudo apt-get install -y intel-oneapi-runtime-opencl intel-oneapi-runtime-compilers
```

Re-run `./install.sh --only platform` (or `awb runtime install ...` for a
single runtime) after either manual step above to pick it up.
