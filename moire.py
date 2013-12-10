#!/usr/bin/env python
import glob
import sys
import subprocess
import time 
import liblo
import os

LINUX_AUDIOINTERFACE = "Komplete"
CSOUNDPATCH = "moire.csd"
PDPATCH = "moiregui2.pd"
PDAPP = "/Applications/Pd-0.44"
CSPORT = 30018
PDPORT = 30019
MANAGERPORT = 30020

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

def exit(delay=1):
    print 
    print "/////////////////////////"
    print "/////  exiting ...  /////"
    print "/////////////////////////"
    print
    time.sleep(delay)
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

def get_proc_status(port):
    """
    Returns False, 'running' or 'unresponsive'
    """
    try:
        s = liblo.Server(port)
        return 'notrunning'
    except liblo.ServerError:
        pass
    # the OSC port is used, so see if we receive pingbacks
    s = liblo.ServerThread()
    def handler(*args):
        ready.append('done')
    s.add_method("/pingback", None, handler)
    t0 = time.time()
    ready = []
    s.start()
    s.send(PDPORT, '/ping', s.port)
    while True:
        if time.time() - t0 > 1:
            timedout = True
            break
        if ready:
            timedout = False
            break
        time.sleep(0.1)
    if timedout:
        return 'unresponsive'
    else:
        return 'running'


def get_pd_status():
    """
    Returns False, 'running' or 'unresponsive'
    """
    return get_proc_status(PDPORT)

def find_pd_binary():
    if DARWIN:
        pdapp = PDAPP
        if not pdapp.endswith("app"):
            pdapp = pdapp + '.app'
        if not os.path.exists(pdapp):
            return None
        return "{pdapp}/Contents/Resources/bin/pd".format(pdapp=pdapp)
    elif LINUX:
        try:
            p = subprocess.check_output("which pd".split())
            if p:
                return p.strip()
        except OSError:
            return None
    else:
        raise RuntimeError("OS not supported")

def is_cs_running():
    try:
        s = liblo.Server(CSPORT)
    except liblo.ServerError:
        return True
    return False

def get_csound_status():
    return get_proc_status(CSPORT)

def check_csound_exit(starttime, exitmsg):
    endtime = time.time()
    if endtime - starttime < 5:
        print 
        print 
        print "ERROR: Csound seems to have crashed:", exitmsg
        print
        print

def launch_csound():
    if DARWIN:
        cs_flags = "-iadc -odac -+rtaudio=pa_cb --env:CSNOSTOP=yes"
        cmd = " ".join(("csound", cs_flags, cs_arduino, cs_patch))
        print "Calling csound with:\n\n" + cmd
        csound_t0 = time.time()
        csoundproc = subprocess.Popen(cmd.split())
        return csoundproc

class Manager(object):
    def __init__(self):
        if DARWIN:
            self.init_darwin()
        else:
            print "Not Implemented"
            exit()
    def init_darwin(self):
        pd_status = get_pd_status()
        if pd_status == 'notrunning':
            pdbin = find_pd_binary()
            os.system("open ./{pdpatch}".format(pd=pdbin, pdpatch=PDPATCH))
        elif pd_status == 'unresponsive':
            print "PD is running but is unresponsive. Kill it and try again"
            exit()
        if is_cs_running():
            print "Csound is already running. Exiting"
            exit()
        self.csoundproc = launch_csound()
        s = liblo.Server(MANAGERPORT)
        def start_csound(path, args):
            if not is_cs_running():
                self.csoundproc = launch_csound()
            else:
                print "csound is already running!"
                self.stop_csound()
                time.sleep(1)
                if is_cs_running():
                    print "could not stop csound!"
                    exit()
                self.csoundproc = launch_csound()
        def quit(path, args):
            self.oscserver.send(CSPORT, '/stop', 1)
            if self.csoundproc is not None and self.csoundproc.poll():
                self.csoundproc.kill()
            self.running = False
        def stop_csound(path, args):
            self.oscserver.send(CSPORT, '/stop', 1)
            time.sleep(0.5)
            if is_cs_running():
                os.system("killall csound")
                print "could not stop csound!"
            else:
                print "Csound stopped. Manager still listening"

        s.add_method("/startcsound", typespec=None, func=start_csound)
        s.add_method("/quit", typespec=None, func=quit)
        s.add_method("/stopcsound", typespec=None, func=stop_csound)
        self.oscserver = s

    def run(self):
        s = self.oscserver
        self.running = True
        from time import sleep
        try:
            while self.running:
                s.recv(200)
                sleep(0.4)
        except KeyboardInterrupt:
            pass
        exit()


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
        man = Manager()
        man.run()
        print "finished Manager"

        # launch PD on the background, we don't own it anymore
        pd_status = get_pd_status()
        print "pd: ", pd_status
        if pd_status == 'notrunning':
            pdbinary = find_pd_binary()
            os.system("open ./{pdpatch}".format(pd=pdbinary, pdpatch=PDPATCH))
        elif pd_status == 'unresponsive':
            print "PD is running but is unresponsive. Kill it and try again"
            exit()
        if is_cs_running():
            print "Csound is already running. Exiting"
            exit()
        csoundproc = launch_csound()
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
        time.sleep(2)
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
            startime = time.time()
            proc_cs.wait()
            check_csound_exit(starttime, proc_cs.poll())
        except KeyboardInterrupt:
            sys.exit(0)

