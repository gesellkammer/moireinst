<CsoundSynthesizer>
<CsOptions>
-b256
-B512
// OSX
--omacro:ARDUINO=/dev/tty.usbmodemfd121
// --omacro:ARDUINO=/dev/tty.usbmodem1a21
// --omacro:ARDUINO=/dev/tty.usbmodem1d11

;; Linux
;--omacro:ARDUINO=/dev/arduinoleo
</CsOptions>
<CsInstruments>
// ksmps  = 16   // this equals a control samplerate of 2600 Hz at 44100
ksmps  = 32      // this equals a control samplerate of 1300 Hz at 44100
0dbfs  = 1
sr     = 44100
nchnls = 4

;; ---------- CONFIG ----------

#define FROM_SOURCE #3#              
#define FROM_MOIRE1 #1#
#define FROM_MOIRE2 #2#   
#define SIMULATE_OUTCHANNEL #4#

;;; OSC
#define ADDR_HOST #"127.0.0.1"#
#define ADDR_PORT #30019#
#define OSCPORT   #30018#
#define UIUPDATERATE #12#

#define ADAPTPERIODX #12#

#define PEDAL_MIN #0.01#
#define PEDAL_MAX #0.99#
#define FADER2_MIN #0.01#
#define FADER2_MAX #0.94#

#define DOPPLER_RAND_BW #0.2#
#define DOPPLER_RAND_FREQ #5#

#define USE_OUTPUT_LIMITER #1#
#define FLUSHSERIALRATE #0.2#
#define FLUSHSERIAL_NUMCHARS #100#
#define LAMP_PORT #11111#
#define LAMP_HOST #"127.0.0.1"#
#define CAM_PORT #22222#
#define CAM_HOST #"127.0.0.1"
#define CAM_CC #99#

;; ------ PRIVATE --------
#define SAW #1#
#define End #1000#
#define TestAudioOut   #1001#
#define SimulateSource #1002#
#define Pingback       #1003#

#define SIMULATE_STRAIN #1#
#define DISTORTION_METHOD_DISTORT1 #1#

;; ------- INIT ----------
ga_source init 0

gkV0, gkV1, gk_freq, gk_v0post, gk_v1post, gk_volpedal init 0
gk_dbL, gk_dbR   init -120
gk_speedwindow   init 0.030
gk_minvariation  init 0.1
gk_smooth        init 0.005
gk_mastergain    init 1
gk_mastermute    init 0
gk_stereomagnify init 1
gk_samplerate    init -1
gk_vusource      init 0
gk_vumasterL     init 0
gk_vumasterR     init 0
gk_volcurve      init 1
gk_vuanalogL     init 0
gk_vuanalogR     init 0
gk_ringmod       init 0.001
gk_gate0         init 60
gk_gate1         init -24
gk_gaindigpre  	 init 1
gk_gaindigpost	 init 1
gk_freqmult      init 1
gk_ringspread    init 1
gk_diggainL      init 1
gk_diggainR      init 1
gk_feedback      init 0.1
gk_feedbackwet   init 0.6
gk_testaudio_state  init 0
gk_vusource_prefader init 0
gk_max0, gk_max1 init 0
gk_min0, gk_min1 init 0
gk_shift         init 8
gk_phasewet      init 0.6
gk_gainanalog	 init 1
gk_gainanalogpost init 1
gk_anagatethreshdb init -90
gk_anagateexp init 60
gk_fader1 init 10
gk_strain init 0
gk_postinit init 0
gk_smoothcurve init 1
gk_smoothgain  init 1
gk_printtrig init 0
gk_dopplerfreq init 0 
gk_lightmax init 1
 
giSerial serialBegin "$ARDUINO", 115200
giOSC OSCinit $OSCPORT

;; ----- TABLES ----------
gi_sinetable ftgen 0, 0, 65536, 10, 1

;; ---------- OPCODES ---------------
opcode gate3lin, k, kkkk
	kx, kx0, kx1, ky1 xin
	if (kx < kx0) then
		kout = 0
	elseif (kx < kx1) then
		kdx = (kx - kx0) / (kx1 - kx0)
		kout = ky1*kdx
	elseif (kx < 1) then
		kdx = (kx - kx1) / (1 - kx1)
		kout = ky1 + (1 - ky1)*kdx
	else
		kout = 1
	endif
	xout kout
endop

opcode gate3cos, k, kkkk
	kx, kx0, kx1, ky1 xin
	if (kx < kx0) then
		kout = 0
	elseif (kx < kx1) then
		kdx = (kx - kx0) / (kx1 - kx0)
		kmu2 = (1-cos(kdx*3.14159265))/2
		// kout = ky0*(1-kmu2)+ky1*kmu2
		kout = ky1*kmu2
	elseif (kx < 1) then
		kdx = (kx - kx1) / (1 - kx1)
		kmu2 = (1-cos(kdx*3.14159265))/2
		kout = ky1*(1-kmu2)+kmu2
	else
		kout = 1
	endif
	xout kout
endop

opcode expgate, a, akkjjj
	a0, kthreshdb, kexp, idiff, iatt, irel xin
	idiff = idiff > 0 ? idiff : 30
	iatt = iatt > 0 ? iatt : 0.001
	irel = irel > 0 ? irel : 0.002
	ilook = iatt * 1
	k0 = kthreshdb - idiff
	kx0 = ampdb(k0)
	ky0 = limit(ampdb(k0 - (kthreshdb-k0)*2), 0, 1)
	ky1 = ampdb(kthreshdb)
	kx1 = ky1
	kamp = rms(a0, 50)
	kgain2 init 0
	if( kamp < kx0 ) then
		kgain = 3.1622776601683795e-05  ;; -90 dB
	elseif (kamp < kx1) then
		kamp2 = ky0 + (ky1 - ky0) * ((kamp - kx0)/(kx1 - kx0))
		kgain = pow(kamp2 / kamp, kexp)
	else
		kgain = 1
	endif
	ktime = port(kgain > kgain2 ? iatt : irel, 0.001)
	kgain2 = portk(kgain, ktime)
	a0 *= interp(kgain2)
	a0 delay a0, ilook
	xout a0
endop

opcode expgatek, k, kkkjjj
	kamp, kthreshdb, kexp, idiff, iatt, irel xin
	idiff = idiff > 0 ? idiff : 30
	iatt = iatt   > 0 ? iatt  : 0.001
	irel = irel   > 0 ? irel  : 0.002
	ilook = iatt * 1
	k0 = kthreshdb - idiff
	kx0 = ampdb(k0)
	ky0 = limit(ampdb(k0 - (kthreshdb-k0)*2), 0, 1)
	ky1 = ampdb(kthreshdb)
	kx1 = ky1
	kgain2 init 0
	if( kamp < kx0 ) then
		kgain = 3.1622776601683795e-05  ;; -90 dB
	elseif (kamp < kx1) then
		kamp2 = ky0 + (ky1 - ky0) * ((kamp - kx0)/(kx1 - kx0))
		kgain = pow(kamp2 / kamp, kexp)
	else
		kgain = 1
	endif
	ktime = port(kgain > kgain2 ? iatt : irel, 0.001)
	xout portk(kgain, ktime)
endop
		
opcode waveshapedist, a, ak
	asig, kamount xin
	kamount = limit(kamount, 0.000001, 0.999)
	kfoo = 2*kamount/(1-kamount)
	asig = (1+kfoo)*asig / (1+(kfoo*abs(asig)))
	asig = limit(asig, -1, 1)
	xout asig
endop

opcode hypersat, a, ak
	asig, kth xin
	kth = max(kth, 0.0000000000001)
	aout = asig / (abs(asig*(1/kth))+1)
	xout aout
endop	

opcode tansat, a, ak
	asig, kdrv xin
	asig = tanh(asig*kdrv)
	xout asig
endop

;; --------- INSTRUMENTS -------------
instr FlushSerialRegularly
	ktrig metro $FLUSHSERIALRATE
	if (ktrig == 1) then
		event "i", 2, 0, 2/kr, $FLUSHSERIAL_NUMCHARS, 2
	endif
endin

instr 2
	inumchars = p4
	id 		  = p5
	kcounter init 0
read1:
	kcounter += 1
	k0 = serialRead(giSerial)
	if ( (k0 >= 0) && (kcounter < inumchars) ) kgoto read1
	serialFlush(giSerial)
	puts "Flushed chars from serial:", kcounter
	printk2 kcounter
	turnoff
endin

instr ReadSerial
	itab_pedal ftgen 0, 0, -1024, -27,  0,0,  512,ampdb(-18),  800,ampdb(-6),  1000,1,  1024,1
	itab_knob  ftgen 0, 0, -1024, -27,  0,0, 32,1, 42,1.001, 137,2,  240,3,  347,4,  469,5,  586,6,  704,7,  827,8,  954,9,  999,10,  1024,10
	
	k_pedal1 init 0
	k_fader1 init 0
	k_fader2 init 0
	k_counter init 0
	
	k_lasttime init 0
	k_samplerate init 0
	
	k0 = serialRead(giSerial)
	if (k0 < 128) kgoto exit
	if( k0 < 140 ) then   
		k0  = serialRead(giSerial) * 128
		k0 += serialRead(giSerial)
		gkV0 = k0/1023 * gk_diggainL
		k0  = serialRead(giSerial) * 128
		k0 += serialRead(giSerial)
		gkV1 = k0/1023 * gk_diggainR
		k_counter += 1
		goto exit
	endif
	if( k0 == 140 ) then
		; pedal1, fader1, fader2, but1, but2
		k0 = serialRead(giSerial)
		k0 *= 128
		k0 += serialRead(giSerial)
		k_pedal1 = k0/1023
		
		k0 = serialRead(giSerial)
		k0 *= 128
		k0 += serialRead(giSerial)
		k_fader1 = k0/1023
		
		k0 = serialRead(giSerial)
		k0 *= 128
		k0 += serialRead(giSerial)
		k_fader2 = k0/1023
		
		gk_but1 = serialRead(giSerial)
		gk_but2 = serialRead(giSerial)
		goto exit
	endif
	if( k0 == 200 ) then
		k_now times
		k_samplerate = k_counter / (k_now - k_lasttime)
		k_counter = 0
		k_lasttime = k_now
		gk_samplerate = k_samplerate
	endif
exit:
	k0 = limit((k_fader2 - $FADER2_MIN)/$FADER2_MAX, 0, 1)
	gk_mix = port(k0, 0.01)    
	k0 = limit((k_pedal1 - $PEDAL_MIN)/$PEDAL_MAX, 0, 1)
	gk_volpedal = tablei(k0*1023, itab_pedal)
	// gk_fader1 = tablei(k_fader1*1000, itab_knob)
	gk_fader1 = table(k_fader1*1000, itab_knob)
endin

;; --- NB: ampdb = db2amp  dbamp = amp2db

opcode oscprint,0,Sk
	Slabel, kvalue xin
	OSCsend gk_printtrig, "127.0.0.1", 31415, "/print", "sf", Slabel, kvalue
endop

instr Brain 
	itab_feedback    ftgen 0, 0, -110, -27,  0,0,	10,0.91,	20,0.91,	30,0.91,	40,0.98,	     50,0.98,	55,0.92,													110,0.92
	itab_feedbackwet ftgen 0, 0, -110, -27,  0,0,				20,0.34,	30,0.8,		40,0.8,	45,0.34, 50,0.34,	60,0,					80,0,		90,0.34,	100,0,		110,0
	itab_phasewet	 ftgen 0, 0, -110, -27,  0,0,										        45,0,  	 50,0.34,	60,0.7,		70,0,		80,0,		90,0.34,	100,0.34,	110,0.34
	itab_ringmod	 ftgen 0, 0, -110, -27,  0,0,																			70,0,		80,0.8,		90,0,		100,0,		110,0
	itab_freqmult    ftgen 0,0, -100,-27,  0,1, 50,1, 80,2,100,2
	
	gk_printtrig = metro(50)
	
	kL = gkV0 * gk_gaindigpre
	kR = gkV1 * gk_gaindigpre
	kavg = (kL + kR)*0.5
	kL = limit(kavg + (kL-kavg)*gk_stereomagnify, 0, 2)
	kR = limit(kavg + (kR-kavg)*gk_stereomagnify, 0, 2)
	kmax = max(kL, kR)
	if (kmax > 1) then
		kL = kL/kmax
		kR = kR/kmax
	endif 
	kL *= expgatek(kL, gk_gate1, gk_gate0, 24, 0.001, 0.002) * gk_gaindigpost
	kR *= expgatek(kR, gk_gate1, gk_gate0, 24, 0.001, 0.002) * gk_gaindigpost
	kbut1 = port(gk_but1, 0.05)
	gk_v0post = ntrpol(kL, pow(kL, gk_smoothcurve)*gk_smoothgain, kbut1)
	gk_v1post = ntrpol(kR, pow(kR, gk_smoothcurve)*gk_smoothgain, kbut1)
	
	k_knobtrig = changed(gk_fader1, gk_postinit)
	if (k_knobtrig == 0) kgoto exit
	ki = gk_fader1*10
	gk_feedback    = tablei(ki, itab_feedback)
	gk_feedbackwet = tablei(ki, itab_feedbackwet)
	gk_phasewet    = tablei(ki, itab_phasewet)
	gk_ringmod     = tablei(ki, itab_ringmod)
	gk_freqmult    = table(gk_ringmod*100, itab_freqmult) * scale(kavg, 2, 1)
exit:
	OSCsend k_knobtrig, $ADDR_HOST, $ADDR_PORT, "/preset", "ffff", \
		gk_feedback, gk_feedbackwet, gk_phasewet, gk_ringmod
	k_buttrig = changed(gk_but1, gk_but2) 
	OSCsend k_buttrig, $ADDR_HOST, $ADDR_PORT, "/buttons", "ii", gk_but1, gk_but2
	k_lightvalue = int(gk_volpedal * gk_lightmax * 1000)
	k_lighttrig = changed(k_lightvalue)
	OSCsend k_lighttrig, $LAMP_HOST, $LAMP_PORT, "/set", "i", k_lightvalue
	OSCsend k_lighttrig, $CAM_HOST, $CAM_PORT, "/A", "i", k_lightvalue
endin

instr PostInit
	gk_postinit = 1
	turnoff
endin

instr UI_osc
	; ---------------------------------
	kcounter       init 0
	kspeedperiod   init 50
	ksmooth        init 7
	kstereomagnify init 1
	kmastergaindb  init 0
	kmute          init 0
	kgate0db       init -40
	kgate1db       init -20
	kstop          init 0
	ktestmode      init 0
	ktestfreq	   init 220
	ktestamp	   init 1
	ktestinterval  init 0
	kstrain 	   init 0
	kpingport	   init 0
	; ---------------------------------
		
	kosctrig metro $UIUPDATERATE
	ksmoothfreq = port(gk_freq, 1/$UIUPDATERATE)

	if (kosctrig == 0) kgoto skip_osc_in
	k0 OSClisten giOSC, "/speedperiod_ms", 	"i", kspeedperiod
	gk_speedwindow = kspeedperiod/1000
	k0 OSClisten giOSC, "/smooth_ms", 		"i", ksmooth
	gk_smooth = ksmooth/1000
	k0 OSClisten giOSC, "/minvariation",	"f", gk_minvariation
	k0 OSClisten giOSC, "/stereomagnify", 	"f", gk_stereomagnify
	k0 OSClisten giOSC, "/mastergaindb", 	"f", kmastergaindb
	k0 OSClisten giOSC, "/mastermute", 		"i", kmute
	k0 OSClisten giOSC, "/gatedig0", 		"f", gk_gate0
	k0 OSClisten giOSC, "/gatedig1", 		"f", gk_gate1
	k0 OSClisten giOSC, "/ringmodboost", 	"f", gk_ringmod
	k0 OSClisten giOSC, "/gainanalog", 		"f", gk_gainanalog
	k0 OSClisten giOSC, "/gaindigpre", 		"f", gk_gaindigpre
	k0 OSClisten giOSC, "/gaindigpost", 	"f", gk_gaindigpost
	k0 OSClisten giOSC, "/ringspread", 		"f", gk_ringspread
	k0 OSClisten giOSC, "/diggainL", 		"f", gk_diggainL
	k0 OSClisten giOSC, "/diggainR", 		"f", gk_diggainR
	k0 OSClisten giOSC, "/feedback", 		"f", gk_feedback
	k0 OSClisten giOSC, "/feedbackwet", 	"f", gk_feedbackwet
	k0 OSClisten giOSC, "/shift", 			"f", gk_shift
	k0 OSClisten giOSC, "/phasewet", 		"f", gk_phasewet
	k0 OSClisten giOSC, "/gainanalogpost",  "f", gk_gainanalogpost
	k0 OSClisten giOSC, "/anagatethreshdb", "f", gk_anagatethreshdb
	k0 OSClisten giOSC, "/anagateexp", 		"f", gk_anagateexp
	k0 OSClisten giOSC, "/smoothing",       "ff", gk_smoothcurve, gk_smoothgain 
	k0 OSClisten giOSC, "/lightmax",        "f", gk_lightmax 
#ifdef SIMULATE_STRAIN
	k0 OSClisten giOSC, "/strain", "f", kstrain
#endif
	k0 OSClisten giOSC, "/stop", "i", kstop
	if( kstop == 1 ) then
		event "i", $End, 0, 0.1
	endif
	k0 OSClisten giOSC, "/ping", "i", kpingport
	if (k0 == 1) then
		event "i", $Pingback, 0, 0.1, kpingport
	endif
	k0 OSClisten giOSC, "/testaudio", "ifff", ktestmode, ktestfreq, ktestamp, ktestinterval
	if (k0 == 0) kgoto skip_test
	if (ktestmode > 0 ) then  ;; asked to turn on, update values
		gk_testfreq = ktestfreq
		gk_testamp  = ktestamp
		gk_testinterval = ktestinterval
		if( gk_testaudio_state == 0) then
			event "i", $SimulateSource, 0, 360000, ktestmode
		elseif ( gk_testaudio_state > 0 && gk_testaudio_state != ktestmode) then ;; we are already on, has the mode changed?
			turnoff2 $SimulateSource, 0, 0.1
			event "i", $SimulateSource, 0, 360000, ktestmode
		endif
			
		gk_testaudio_state = ktestmode
	elseif (gk_testaudio_state > 0) then   ;; asked to turnoff, are we on?
		turnoff2 $SimulateSource, 0, 0.1
		gk_testaudio_state = 0
	endif
skip_test:
skip_osc_in:
	OSCsend kosctrig, $ADDR_HOST, $ADDR_PORT, "/info", "fffffffffffffffff", \
				ksmoothfreq, gk_mix, gk_volpedal, gkV0, gkV1, gk_v0post, gk_v1post, \ 
				gk_vumasterL, gk_vumasterR, gk_vusource, gk_samplerate, gk_vuanalogL, \
				gk_vuanalogR, gk_vusource_prefader, gk_fader1, gk_strain, gk_dopplerfreq

	gk_mastergain = port(ampdb(kmastergaindb) * (1-kmute), 0.05)
	gk_strain = kstrain

endin

;; --------------------------------------------------------------
instr $Pingback
	iport = p4
	OSCsend 1, "127.0.0.1", iport, "/pingback", "i", 1
	turnoff
endin

instr CalculateSpeed
	i_amptable ftgen 0, 0, -1001, 7,   0, 1, 0, 4, 0.001, 11, 0.063095734448, 4, 1, 980, 1
	iperdur = ksmps/sr
	kzeros0, kzeros1, kperiods, kfreq0_raw, kfreq1_raw init 0
	kmin0, kmin1 init 1
	kmax0, kmax1 init 0
	kmin0_new, kmin1_new init 1
	kmax0_new, kmax1_new init 0
	
	k_speedwindow = max(gk_speedwindow, 0.001)
	k_speedwindow_ks = int(k_speedwindow / iperdur)
	
	kminvariation = gk_minvariation
	
	kv0 = gkV0
	kv1 = gkV1
	
	kmin0_new = min(kmin0_new, kv0)
	kmax0_new = max(kmax0_new, kv0)
	kmin1_new = min(kmin1_new, kv1)
	kmax1_new = max(kmax1_new, kv1)
	
	kthresh0 = (kmax0 + kmin0) * 0.5
	kthresh1 = (kmax1 + kmin1) * 0.5
	
	kzero0 trigger kv0, kthresh0, 2  // 0=raising, 1=falling, 2=both
	kzero1 trigger kv1, kthresh1, 2  // 0=raising, 1=falling, 2=both

	kismoving0 = ((kmax0 - kmin0) > kminvariation) ? 1 : 0
	kismoving1 = ((kmax1 - kmin1) > kminvariation) ? 1 : 0

	kzeros0 += (kismoving0 * kzero0)
	kzeros1 += (kismoving1 * kzero1)
	
	if ((kperiods % k_speedwindow_ks) == 0) then
		kfreq0_raw = kzeros0 / k_speedwindow
		kfreq1_raw = kzeros1 / k_speedwindow
		kzeros0 = 0
		kzeros1 = 0
		// kperiods = 0
	endif
	
	k_minmax_ks = k_speedwindow_ks * $ADAPTPERIODX
	if ((kperiods % k_minmax_ks) == 0) then
		kmin0 = (kmin0 + kmin0_new)*0.5
		kmin1 = (kmin1 + kmin1_new)*0.5
		kmax0 = (kmax0 + kmax0_new)*0.5
		kmax1 = (kmax1 + kmax1_new)*0.5
		kmin0_new = kv0
		kmin1_new = kv1
		kmax0_new = kv0
		kmax1_new = kv1
		gk_max0 = kmax0
		gk_max1 = kmax1
		gk_min0 = kmin0
		gk_min1 = kmin1
	endif   
	
	gk_freq  = portk((kfreq0_raw+kfreq1_raw)*0.5, gk_smooth)
	kperiods += 1
endin

opcode linlin, k, kkkkk
	kx, kx0, kx1, ky0, ky1 xin
	kout = (kx - kx0)/(kx1-kx0)
	kout = ky0 + kout*(ky1-ky0)
	xout kout
endop

opcode freqshift, aa, akk
	ain, kfreq, kamp xin
	areal, aimag hilbert ain
	asin oscili kamp, kfreq, gi_sinetable
	acos oscili kamp, kfreq, gi_sinetable, 0.25
	amod1 = areal*acos
	amod2 = aimag*asin
	aup   = amod1 - amod2
	adown = amod1 + amod2
	xout adown, aup
endop

opcode freqshift2, aa, ak
	ain, kfreq, kamp xin
	areal, aimag hilbert ain
	kfreqpos = abs(kfreq)
	asin oscili 1, kfreqpos, gi_sinetable
	acos oscili 1, kfreqpos, gi_sinetable, 0.25
	amod1 = areal*acos
	amod2 = aimag*asin
	aup   = amod1 - amod2
	adown = amod1 + amod2
	kwhich = port(kfreq < 0 ? 0 : 1, 0.005)
	;;kwhich = interp(kfreq < 0 ? 0 : 1)
	;;a1 = adown*kwhich + aup*(1-kwhich)
	;;a2 = aup*kwhich + adown*(1-kwhich)
	a1 = ntrpol(aup, adown, kwhich)
	a2 = ntrpol(adown, aup, kwhich)
	xout a1, a2
endop

opcode freqshift1, ak, ak
	ain, kdeltafreq xin
	kabsdelta = abs(kdeltafreq)
	areal, aimag hilbert ain
	asin oscili 1, kabsdelta, gi_sinetable
	acos oscili 1, kabsdelta, gi_sinetable, 0.25
	amod1 = areal*acos
	amod2 = aimag*asin
	aup   = amod1 - amod2
	;adown = amod1 + amod2
	adown = pinkish(0.5)
	kwhich = port(kdeltafreq < 0 ? 0 : 1, 0.05)

	aout ntrpol adown, aup, kwhich
	xout aout, kwhich
endop
		
opcode lforange, k, kkki
	kfreq, kmin, kmax, imode xin
	kout lfo kmax-kmin, kfreq, imode
	kout += (kmax+kmin) * 0.5
	xout kout
endop

opcode fdn, a, akkkkkjjjjj
	/*
	kgain: 0-1, kdelaytime: 0.002-0.5
	kcutoff: cutoff of lowpass filter at output of delay line
	kfreq: frequency of random noise
	pitchmod: amplitude of random noise (0-10)
	tapmix: 0=only feedback, 1=only delay
	delratio: a multiplier to the delays
	delmin: minimum delay
	delmax: maximum delay
	cutoffdev: deviation of the cutoff, as a ratio, for each feedback loop
	*/
	ain, kgain, kdelaytime, kcutoff, kfreq, kpitchmod, i_tapmix, i_delratio, i_delmin, i_delmax, i_cutoffdev xin
	itapmix = i_tapmix >= 0 ? i_tapmix : 0.2
	ifiltgain = 1 - itapmix
	itapgain = itapmix
	idelratio = (i_delratio >= 0 ? i_delratio : 1)
	idelmin = (i_delmin >= 0 ? i_delmin : 0.0663) * idelratio
	idelmax = (i_delmax >= 0 ? i_delmax : 0.0971) * idelratio
	idel1 = idelmin
	idel2 = idelmin + (idelmax - idelmin) * 0.34
	idel3 = idelmin + (idelmax - idelmin) * 0.55
	idel4 = idelmax
	icutoffdev = i_cutoffdev >= 0 ? i_cutoffdev : 0.2
	imaxdelay = 0.2
	afilt1, afilt2, afilt3, afilt4 init 0	
	kgain *= 0.70710678117
	
	k1 randi .001, 3.1 * kfreq, .06
	k2 randi .0011, 3.5 * kfreq, .9
	k3 randi .0017, 1.11 * kfreq, .7
	k4 randi .0006, 3.973 * kfreq, .3
	
	atap multitap ain, 0.00043, 0.0615, \
	                   0.00268, 0.0298, \ 
					   0.00485, 0.0572, \
					   0.00595, 0.0708, \
					   0.00741, 0.0797, \
					   0.0142, 0.134, \
					   0.0217, 0.181, \
					   0.0272, 0.192, \
					   0.0379, 0.346, \
					   0.0841, 0.504
	adum1 delayr imaxdelay 
	adel1 deltapi idel1 * kdelaytime + k1*kpitchmod
	delayw ain + afilt2 + afilt3

	adum2 delayr imaxdelay
	adel2 deltapi idel2 * kdelaytime + k2*kpitchmod
	delayw ain - afilt1 - afilt4
	
	adum3 delayr imaxdelay
	adel3 deltapi idel3 * kdelaytime + k3*kpitchmod
	delayw ain + afilt1 - afilt4

	adum4 delayr imaxdelay
	adel4 deltapi idel4 * kdelaytime + k4*kpitchmod
	delayw ain + afilt2 - afilt3

	afilt1 tone adel1*kgain, kcutoff * (1 - icutoffdev*0.5)
	afilt2 tone adel2*kgain, kcutoff * (1 - icutoffdev*0.167)
	afilt3 tone adel3*kgain, kcutoff * (1 + icutoffdev*0.167)
	afilt4 tone adel4*kgain, kcutoff * (1 + icutoffdev*0.5)

	afilt = sum(afilt1, afilt2, afilt3, afilt4) * 0.70710678117
	aout ntrpol afilt, atap, itapmix
	xout aout
endop

opcode fbcombx, a, akkj
	ain, kfback, kdel, igain xin
	igain = igain >= 0 ? igain : 0.7071
	abuf delayr 0.5
	atap deltapx interp(kdel), 16
	delayw ain * igain + atap*(kfback*igain)
	xout atap
endop

opcode fbcomb, a, akk
	ain, kfback, kdel xin
	krvt = port(-4.605170185988091 * kdel / log(kfback), 0.001)
	aout vcomb ain, krvt, interp(kdel), 0.5
	xout aout
endop

opcode ffcomb, a, akkj
	ain, kfback, kdel, igain xin
	igain = igain >= 0 ? igain : 0.7071
	abuf delayr 0.5
	atap deltap3 interp(kdel)
	delayw ain
	ain  *= igain
	atap *= kfback*igain 
	xout ain + atap
endop

opcode ffcomb_a, a, aka
	ain, kfback, adel xin
	atap vdelayx ain, adel, 0.5, 16
	ain  *= 0.707
	atap *= kfback*0.707 
	xout ain + atap
endop

opcode tubesat, a,akk
	a0, kdrive, klim xin
	ahgh butterhp a0, klim
	a0   butterlp a0, klim
	a0 *= kdrive
	a0 = 0.5*pow(a0+1.41, 2) - 1
	a0 *= sqrt(1/kdrive)
	a0 += delay(ahgh, 4/sr)
	xout a0
endop

;; --------------------------------------------------------------
instr Audio
	kuimetro = metro($UIUPDATERATE)
	
	;; --- CURVES ---
	
	// itab_sigmoid ftgen	0,0, 257, 9, .5,1,270,1.5,.33,90,2.5,.2,270,3.5,.143,90,4.5,.111,270
	itab_sigmoid ftgen	0,0, 257, 9, .5,1,270
	
	;; --- SOURCE ---
	aSource inch $FROM_SOURCE
	ksourcegain = port(gk_volpedal, 0.025)
	
	gk_vusource_prefader = max_k(aSource, kuimetro, 1)
	;; aSource *= interp(ksourcegain)
	aSource *= ksourcegain
	aMoireL   inch $FROM_MOIRE1
	aMoireR   inch $FROM_MOIRE2
	
	;; --- ANALOG ---
	kgainanalog = gk_gainanalog * ksourcegain
	aAnaL = aMoireL * kgainanalog
	aAnaR = aMoireR * kgainanalog
	aAnaL = expgate(aAnaL, gk_anagatethreshdb, gk_anagateexp)
	aAnaR = expgate(aAnaR, gk_anagatethreshdb, gk_anagateexp)
	
#ifdef DISTORTION_METHOD_DISTORT1
/*
	adistL distort aAnaL, gk_strain, itab_sigmoid
	adistR distort aAnaR, gk_strain, itab_sigmoid
*/	
kpre = 1+gk_strain*2
kpost = 1/limit(kpre, 0.00001, 1)
	adistL distort1 aAnaL, kpre, kpost, 0.5, 0.5, 1
	adistR distort1 aAnaR, kpre, kpost, 0.5, 0.5, 1
	aAnaL ntrpol aAnaL, adistL, gk_strain
	aAnaR ntrpol aAnaR, adistR, gk_strain
#else
	adistL hypersat aAnaL, gk_strain
	adistR hypersat aAnaR, gk_strain
	aAnaL ntrpol aAnaL, adistL, gk_strain
	aAnaR ntrpol aAnaR, adistR, gk_strain
#end
	aAnaL *= gk_gainanalogpost
	aAnaR *= gk_gainanalogpost
	gk_vuanalogL = max_k(aAnaL, kuimetro, 1)
	gk_vuanalogR = max_k(aAnaR, kuimetro, 1)

	denorm aSource, aAnaL, aAnaR
	
	aDigL = tansat(aSource, 2)
	aDigR = aDigL
	;; --- DOPPLER ---
	if( gk_but2 == 0 ) kgoto skip_shift
	
	;;aDigL = tubesat(aDigL, 1, 1200)
	
	;;aDigR = tubesat(aDigR, 1, 1200)
	
	goto skip_shift
	
	
	irandbw = $DOPPLER_RAND_BW
	kshiftbw = gk_shift * (1-irandbw*0.5+randi(irandbw, $DOPPLER_RAND_FREQ))
	kdeltafreq = port((gk_v1post - gk_v0post)/(gk_v0post+gk_v1post) * kshiftbw + 0.25, 0.01)
	// we divide by 2 because to calculate the deviation of each channel
	gk_dopplerfreq = kdeltafreq 
	adown, aup freqshift aSource, kdeltafreq*0.5, 1
	aDigL = adown
	aDigR = aup
	
skip_shift:

	; --- comb ---
	itab_speed2ringenv ftgen 0, 0, -2000, -27, 0,0,   2,0,  16,0.01,  30,1,  400,1, 2000,1
	
	kmaxlevel = gk_v0post+gk_v1post
	kphasecontrast = scale(gk_phasewet, 0.0009, 0.0005)
	
	kdelL = gk_v0post/kmaxlevel*kphasecontrast + 0.005
	kdelR = gk_v1post/kmaxlevel*kphasecontrast + 0.002// + kavgdiff*0.005 + 0.005
	kdelL = max(kdelL, 0.0009)
	kdelR = max(kdelR, 0.0009)
	kdelL = port(kdelL, 0.001)
	kdelR = port(kdelR, 0.001)
	
	itab_speed2fback   ftgen 0, 0, -1000, -27, 0,0.85, 40,0.85, 120,0.91, 300,0.9999,1000,.9999
	kfback = tablei(gk_freq, itab_speed2fback)
	kfback *= scale(gk_phasewet, 0.99, 0.85)
	
	aphL  = fbcombx(aDigL, kfback, kdelL)
	aphR  = fbcombx(aDigR, kfback, kdelR)	
	
	kcross = port(gk_phasewet, 0.005)
	aDigL = ntrpol(aDigL, aphL, kcross) * interp(gk_v0post)
	aDigR = ntrpol(aDigR, aphR, kcross) * interp(gk_v1post)
	
	; --- RINGMOD BOOST ---
	kringfreq = port(gk_freq*gk_freqmult, 0.005)
	kringenv  = port(tablei(kringfreq, itab_speed2ringenv), 0.005)
	
	; --- OUT ---
	aOutL ntrpol aAnaL, aDigL, gk_mix
	aOutR ntrpol aAnaR, aDigR, gk_mix
		
	aup, adown freqshift aOutL, kringfreq, 1
	aRingL = ntrpol(adown, aup, gk_ringspread) * kringenv
	aup, adown freqshift aOutR, kringfreq, 1
	aRingR = ntrpol(aup, adown, gk_ringspread) * kringenv
	
	kcross = port(gk_ringmod, 0.005)
	aOutL = ntrpol(aOutL, aRingL, kcross)
	aOutR = ntrpol(aOutR, aRingR, kcross)
	
	; ---- control feedback resonance ---- 
	aOutM = (aOutL+aOutR)*0.70710678117
	kamp = pow(max_k(aOutM, metro(20), 1), 2)
	kspeedindex = pow(limit(gk_freq/200, 0, 1), 0.5)
	kfdn_cutoff   = port(scale(kamp, 12000, 4000), 0.005)
	kfdn_freq     = port(scale(kspeedindex, 0.3, 0.1), 0.01)
	kfdn_pitchmod = port(scale(kspeedindex, 0.5, 0.05), 0.005)
	
	// fdn(ain, kgain, kdelaytime, kcutoff, kfreq, kpitchmod, i_tapmix, i_delratio, i_delmin, i_delmax, i_cutoffdev) : a
	kfback = port(gk_feedback, 0.01)
	
	aWetL = fdn(aOutL, kfback, 0.15, kfdn_cutoff, kfdn_freq, kfdn_pitchmod, 0.3, 1, 0.063, 0.091)
	aWetR = fdn(aOutR, kfback, 0.15, kfdn_cutoff, kfdn_freq, kfdn_pitchmod, 0.3, 1, 0.063, 0.091)

	kcross = port(gk_feedbackwet, 0.01)
	aOutL ntrpol aOutL, aWetL, kcross
	aOutR ntrpol aOutR, aWetR, kcross
	
	aOutL *= gk_mastergain
	aOutR *= gk_mastergain

	; -- limiter --
	aOutL = compress(aOutL, aOutL, 0, 87, 93, 100, 0.001, 0.010, 0.004)
	aOutR = compress(aOutR, aOutR, 0, 87, 93, 100, 0.001, 0.010, 0.004)
	
	; -- gui meters -- 
	gk_vumasterL = max_k(aOutL, kuimetro, 1)
	gk_vumasterR = max_k(aOutR, kuimetro, 1)
	gk_vusource  = max_k(aSource, kuimetro, 1)
	
	outch 1, aOutL
	outch 2, aOutR
	
endin

;; --------------------------------------------------------------
instr $SimulateSource
	imode = p4
	if (imode == 1) then
		imode = 0
		isin = 0
	elseif (imode == 2) then 
		imode = 10		
		isin = 0
	elseif (imode == 3) then 
		imode = 12
		isin = 0
	elseif (imode == 4) then
		imode = 0
		isin = 1
	endif
	kfreq0 = port(gk_testfreq, 0.005)
	kfreq1 = kfreq0*semitone(gk_testinterval)
	aenv = adsr(0.1, 0, 1, 0.1)*port(gk_testamp, 0.005)
	asin0 oscili 1, kfreq0
	asin1 oscili 1, kfreq1
	avco0 vco2 1, kfreq0, imode
	avco1 vco2 1, kfreq1, imode
	kosc2gain = gk_testinterval == 0 ? 0 : 1
	avco0 = (avco0 + avco1*kosc2gain)*0.707
	asin0 = (asin0 + asin1*kosc2gain)*0.707
	
	aout ntrpol avco0, asin0, isin
	outch $SIMULATE_OUTCHANNEL, aout*aenv
endin

instr $End
	serialEnd giSerial
	event "e", 0, 0, 0.1 
endin

</CsInstruments>

;; --------------------------------------------------------------
;; --------------------------------------------------------------
;; --------------------------------------------------------------
<CsScore>
i "ReadSerial" 0 36000
i "CalculateSpeed" 0 36000
i "Brain" 0 36000
i "Audio" 1 36000
i "FlushSerialRegularly" 1 36000
i "UI_osc" 0 36000
i "PostInit" 1 0.01
i 2 0 0.1 32000 1  ;; flush this number of characters at the beginning of the performance
e 
</CsScore>
</CsoundSynthesizer>