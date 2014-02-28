These are the instructions to install the camera controller for the moire instrument

# Installation (OSX, Linux)

* Puredata (PD) >= 0.45, vanilla, 32 bits
* GEM >= 0.93.3

# Usage

* Connect the USB camera
* Open the PD patch (moire-camera-fade.pd)
* Check that GEM is inited properly
* In the patch, set the resolution
* If on OSX, click on "dialog" to select the camera, if there
  are more than one in your system
* The patch will receive any OSC message with <= 3 chars, with 
  an integer value between 0-1000
  something like: oscsend localhost 22222 /A i 999



