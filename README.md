# Software 

* moire.app
* midilamp.app
* moirecam.app

### moirecam.app

* First connect the USB camera
* Open the app. This is an openFrameworks app, 
	* built for OSX >= 10.6, checked with 10.6.8, 10.8.5 and 10.9

#### API ####

	OSC: 22222
  
	/minbrigtness value (int, 0-1000)  
		Sets the minimum brightness. This value will persist  
		
	/set value (int, 0-1000)  
		Sets the brightness  

### midilamp.app

* Begin with everything unplugged
* Plug the Audio cable between lamp and DAC (the black metal box with the label "OSCLAMP")
* Plug the Power source (DC 10V)
* Plug the USB cable
* Turn the lamp on by pressing on the capacitive button on the front of the lamp. Press 3 times (maximum brightness). Any other brightness setting will generate distortion (the internal PWM of the lamp)
* Launch the app
* The app launches in the background. To check that it is working, the LED in the DAC box should blink fast (5 times a second)
* To quit the app, click on the icon on the dock. A window will appear with a "QUIT" button.

> NB: **NEVER** plug the Audio cabel with the lamp plugged. Always remove the Power source first.

#### API ####  

	OSC: 11111
	  
	/set value (int 0-1000)  
	/stop  
	
# moire.app

## Installation

* Install csound 6.0 or higher
* Install Pd-Extended 0.44 or higher

## Connections

* Connect the Moire-Instrument to USB
* Connect the internal audio interface to USB
* Select the internal audio interface (Komplete 6) as your default interface
* Samplerate: 44100

## Launching
* Launch the moire app (moire.app)
* The moire.app will launch PD. 
* PD is only used as a user-interface, keep DSP off
* To quit, press the QUIT button.

> NB: The app will not launch if the moire-instrument is not connected


