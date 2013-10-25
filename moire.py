#!/usr/bin/env python
import glob
import sys
import subprocess
from time import sleep
import liblo
import os

LINUX_AUDIOINTERFACE = "Komplete"
CSOUNDPATCH = "moire.csd"
PDPATCH = "moiregui2.pd"
CSPORT = 30018
PDPORT = 30019

if sys.platform == 'darwin':
    DARWIN = True
    LINUX = False
if sys.platform == 'linux2':
    LINUX = True
    DARWIN = False

def find_arduino():
    if DARWIN:
        arduino = glob.glob("/dev/tty*usb*")
        if arduino:
            return arduino[0]
    elif LINUX:
        arduino = glob.glob("/dev/*arduino*")
        if arduino:
            return arduino[0]
        else:
            arduino = glob.glob("/dev/tty*ACM*")
            if arduino:
                return arduino[0]

def exit(delay=5):
    print 
    print "/////////////////////////"
    print "/////  exiting ...  /////"
    print "/////////////////////////"
    print
    sleep(delay)
    sys.exit(0)


def linux_find_audiodevice(kind, pattern, backend='pa_cb', debug=False):
    """kind: in or out"""
    import re, fnmatch
    if kind == 'out':
        flag = '-odac99'
        patt = "[0-9]: dac[0-9].+"
    else:
        flag = '-iadc99'
        patt = "[0-9]: adc[0-9].+"
    cmd = "csound -+rtaudio={backend} {flag} {patch}".format(backend=backend, flag=flag, patch=cs_patch)
    if debug:
        print "cmd: ", cmd
    p = subprocess.Popen(cmd.split(), stderr=subprocess.PIPE, stdout=subprocess.PIPE)
    _, stderr = p.communicate()
    matches = re.findall(patt, stderr)
    if debug:
        print matches
    for match in matches:
        if fnmatch.fnmatch(match, pattern):
            return int(match.strip()[0])
    return None

def linux_find_audiodevices(pattern, backend='pa_cb'):
    indev, outdev = linux_find_audiodevice('in', pattern, backend), linux_find_audiodevice('out', pattern, backend)
    return indev, outdev

def is_pd_running():
    try:
        s = liblo.Server(PDPORT)
    except liblo.ServerError:
        return True
    return False

def is_cs_running():
    try:
        s = liblo.Server(CSPORT)
    except liblo.ServerError:
        return True
    return False

if __name__ == '__main__':
    arduino = find_arduino()
    cs_arduino = "--omacro:ARDUINO={arduino}".format(arduino=arduino)
    cs_patch = "./%s" % CSOUNDPATCH

    if not arduino:
        print
        print "ERROR: could not find the MOIRE usb device"
        print "Is it connected??"
        print
        exit()

    if DARWIN:
        # launch PD on the background, we don't own it anymore
        if not is_pd_running():
            os.system("open ./{pdpatch}".format(pdpatch=PDPATCH))
        if is_cs_running():
            print "Csound is already running. Exiting"
            exit()
        # wait on csoundd
        cs_flags = "-iadc -oadc -+rtaudio=pa_cb --env:CSNOSTOP=yes"
        cmd = " ".join(("csound", cs_flags, cs_arduino, cs_patch))
        print "Calling csound with:\n\n" + cmd
        csoundproc = subprocess.Popen(cmd.split())
        try:
            csoundproc.wait()
        except KeyboardInterrupt:
            sys.exit(0)

    elif LINUX:
        if not is_pd_running():
            proc_pd = subprocess.Popen("nohup pd -noaudio -nrt ./{pdpatch}".format(pdpatch=PDPATCH).split())
        if is_cs_running():
            print "Csound is already running!"
            sys.exit(0)

        indev, outdev = linux_find_audiodevices('*%s*' % LINUX_AUDIOINTERFACE)
        print "Audio Devices:", indev, outdev
        if indev is None or outdev is None:
            print "Could not find audiodevice. Is it plugged in?"
            exit()

        # os.system("./linux-startup.sh")
        indev  = "adc:plughw:K6,0"
        outdev = "dac:plughw:K6,0"
        cs_flags = "-d -i{indev} -o{outdev} -+rtaudio=alsa --env:CSNOSTOP=yes".format(indev=indev, outdev=outdev)
        cs_exe = "chrt 6 csound"
        cmd = " ".join((cs_exe, cs_flags, cs_arduino, cs_patch))
        proc_cs = subprocess.Popen(cmd.split())
        sleep(2)
        print "Calling csound with:\n\n" + cmd
        print
        print
        print 
        print "==================================================="
        print "  Press CTRL-C to stop or press the 'STOP' button  "
        print "==================================================="
        print 
        print
        try:
            proc_cs.wait()
        except KeyboardInterrupt:
            sys.exit(0)
