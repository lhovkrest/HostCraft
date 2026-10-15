"""Prepare pinned Android runtime assets and APK executables. Python 3.12+, JDK, NDK r28.
Usage: python tool/prepare_android.py --ndk PATH [--arch arm64-v8a|x86_64|all]
"""
import argparse, hashlib, os, pathlib, shutil, subprocess, tarfile, urllib.request, zipfile

PROJECT = pathlib.Path(__file__).resolve().parents[1]
SPECS = {
    'arm64-v8a': ('arm64','aarch64','aarch64-linux-android',
        '8d41ec401ee59f7722df60ed991f81ad146e130452804bfdd8a05d3436f7bbfe',
        'cd3fa1cedac40a71d80a120e6353e08836308840340b58e659e8f25d00601f66'),
    'x86_64': ('x86_64','amd64','x86_64-linux-android',
        'cb88723961f5f9ad63afa1f212eb199816c27cabfd7dc66567bde1d8fb69713b',
        'e78d463d93aa1e3ec36a06ded5a1f4fe879905fdceb865df8f4cef6124f8a555')}

def fetch(url, destination, digest):
    if not destination.exists():
        print('Downloading', url, flush=True)
        with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent':'HostCraft-build/0.1'})) as r:
            with destination.open('wb') as out: shutil.copyfileobj(r,out)
    if hashlib.file_digest(destination.open('rb'),'sha256').hexdigest()!=digest:
        raise RuntimeError('Checksum mismatch: '+str(destination))

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--ndk',required=True)
    parser.add_argument('--arch',default='arm64-v8a',choices=[*SPECS,'all'])
    args=parser.parse_args()
    cache=PROJECT/'build'/'native-cache'; cache.mkdir(parents=True,exist_ok=True)
    assets=PROJECT/'android/app/src/main/assets'; assets.mkdir(parents=True,exist_ok=True)
    classes=cache/'classes'; classes.mkdir(exist_ok=True)
    subprocess.run(['javac','--release','17','-d',str(classes),str(PROJECT/'native/Main.java')],check=True)
    subprocess.run(['jar','cf',str(assets/'hostcraft-bootstrap.jar'),'-C',str(classes),'.'],check=True)
    host='windows-x86_64' if os.name=='nt' else ('darwin-x86_64' if os.uname().sysname=='Darwin' else 'linux-x86_64')
    clang=pathlib.Path(args.ndk)/'toolchains/llvm/prebuilt'/host/'bin'/('clang.exe' if os.name=='nt' else 'clang')
    for abi in SPECS if args.arch=='all' else [args.arch]:
        javaArch,playArch,triple,javaHash,playHash=SPECS[abi]
        archive=cache/f'jre21-{javaArch}.tar.xz'
        fetch(f'https://github.com/AngelAuraMC/angelauramc-openjdk-build/releases/download/download_jre21/jre21-android-{javaArch}.tar.xz',archive,javaHash)
        with tarfile.open(archive) as tar, zipfile.ZipFile(assets/f'runtime-{abi}.zip','w',zipfile.ZIP_DEFLATED) as z:
            for member in tar.getmembers():
                name=member.name.removeprefix('./')
                if member.isfile() and not name.startswith('bin/'):
                    z.writestr(name,tar.extractfile(member).read())
        libs=PROJECT/'android/app/src/main/jniLibs'/abi; libs.mkdir(parents=True,exist_ok=True)
        fetch(f'https://github.com/playit-cloud/playit-agent/releases/download/v0.17.1/playit-linux-{playArch}',libs/'libplayit.so',playHash)
        subprocess.run([str(clang),f'--target={triple}26','-O2','-fPIE','-pie','-Wl,-z,max-page-size=16384',
            str(PROJECT/'native/hostcraft_exec.c'),'-ldl','-o',str(libs/'libhostcraft_exec.so')],check=True)
        print('Prepared',abi,flush=True)

if __name__=='__main__': main()
