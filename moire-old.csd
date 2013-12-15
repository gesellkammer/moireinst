<CsoundSynthesizer>
<CsOptions>
-b1024   
-B2048
; OSX
;--omacro:ARDUINO=/dev/tty.usbmodemfd111
;--omacro:ARDUINO=/dev/tty.usbmodem1a21
--omacro:ARDUINO=/dev/tty.usbmodem1d11

;; Linux
;--omacro:ARDUINO=/dev/arduinoleo
</CsOptions>
<CsInstruments>

;ksmps  = 16   ; this equals a control samplerate of 2600 Hz at 44100
ksmps  = 32   ; this equals a control samplerate of 1300 Hz at 44100
nchnls = 4
0dbfs  = 1
sr     = 44100

;; ---------- CONFIG ----------

; audio channels
#define FROM_SOURCE #1#              
#define FROM_MOIRE1 #4#
#define FROM_MOIRE2 #3#                

#define ADDR_HOST #"127.0.0.1"#
#define ADDR_PORT #30019#
#define OSCPORT   #30018#
#define ADAPTPERIODX #12#
#define UIUPDATERATE #16#

#define FLUSHSERIALRATE #0.05#
#define FLUSHSERIAL_NUMCHARS #400#

;; ------ PRIVATE --------
#define SAW #1#
#define End #1000#
#define TestAudioOut #1001#

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
gk_gate0         init ampdb(-40)
gk_gate1         init ampdb(-24)
gk_gain_analog   init 1
gk_gain_digital  init 1
gk_freqmult      init 1
gk_ringspread    init 1
gk_diggainL      init 1
gk_diggainR      init 1
gk_feedback      init 0.1
gk_feedbackwet   init 0.6
gk_testaudio_on  init 0

/*
;; ------ ALWAYS ON -------
alwayson "ReadSerial"
alwayson "CalculateSpeed"
alwayson "Brain"
alwayson "Audio"
;;alwayson "FlushSerialRegularly"
*/ 

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
		; kout = ky0*(1-kmu2)+ky1*kmu2
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
	printk2 id
	turnoff
endin

instr ReadSerial
	k_fader1 init 0
	k_pedal1 init 0
	k_counter init 0
	kVal = serialRead(giSerial)
	k_lasttime init 0
	k_samplerate init 0
	
	k0 = limit((k_fader1 - 0.03)/0.92, 0, 1)
	gk_mix = port(k0, 0.001)    
	k0 = limit((k_pedal1 - 0.02)/0.96, 0, 1)
	gk_volpedal = port(pow(k0, gk_volcurve), 0.001)
 
	if (kVal < 128) kgoto exit
	if( kVal < 140 ) then   
		k0  = serialRead(giSerial)
		k0 *= 128
		k0 += serialRead(giSerial)
		gkV0 = k0/1023 * gk_diggainL
		k0  = serialRead(giSerial)
		k0 *= 128
		k0 += serialRead(giSerial)
		gkV1 = k0/1023 * gk_diggainR
		k_counter += 1
		goto exit
	endif
	if( kVal == 140 ) then
		k0 = serialRead(giSerial)
		k0 *= 128
		k0 += serialRead(giSerial)
		k_fader1 = (k0/1023)
		k0 = serialRead(giSerial)
		k0 *= 128
		k0 += serialRead(giSerial)
		k_pedal1 = k0/1023
		k_now times
		if( k_now - k_lasttime > 1) then
			k_samplerate = k_counter / (k_now - k_lasttime)
			k_counter = 0
			k_lasttime = k_now
			gk_samplerate = k_samplerate
		endif
	endif
exit:
endin

;; --- NB: ampdb = db2amp  dbamp = amp2db
instr Brain 
	kavg = (gkV0 + gkV1)*0.5
		k0 = kavg + (gkV0-kavg)*gk_stereomagnify
		k1 = kavg + (gkV1-kavg)*gk_stereomagnify
		kmax = max(k0, k1)
		if (kmax > 1) then
			k0 = k0/kmax
			k1 = k1/kmax
		endif
		gk_v0post = gate3lin(k0, gk_gate0, gk_gate1, gk_gate0) * gk_gain_digital
		gk_v1post = gate3lin(k1, gk_gate0, gk_gate1, gk_gate0) * gk_gain_digital
		gk_freqmult = scale((gkV0+gkV1)*0.5, 3, 2)
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
	ktestaudio     init 0
	; ---------------------------------
		
	ksendtrig metro $UIUPDATERATE
	ksmoothfreq = port(gk_freq, 1/$UIUPDATERATE)

	if (ksendtrig == 0) kgoto skip_osc_in
	k0 OSClisten giOSC, "/speedperiod_ms", "i", kspeedperiod
	gk_speedwindow = kspeedperiod/1000
	k0 = OSClisten(giOSC, "/minvariation", "f", gk_minvariation)
	k0 = OSClisten(giOSC, "/smooth_ms", "i", ksmooth)
	gk_smooth = ksmooth/1000
	k0 = OSClisten(giOSC, "/stereomagnify", "f", gk_stereomagnify)
	k0 = OSClisten(giOSC, "/mastergaindb", "f", kmastergaindb)
	k0 = OSClisten(giOSC, "/mastermute", "i", kmute)
	k0 = OSClisten(giOSC, "/gate0db", "f", kgate0db)
	gk_gate0 = ampdb(kgate0db)
	k0 = OSClisten(giOSC, "/gate1db", "f", kgate1db)
	gk_gate1 = ampdb(kgate1db)
	k0 = OSClisten(giOSC, "/ringmodboost", "f", gk_ringmod)
	k0 OSClisten giOSC, "/gainanalog", "f", gk_gain_analog
	k0 OSClisten giOSC, "/gaindigital", "f", gk_gain_digital
	k0 OSClisten giOSC, "/ringspread", "f", gk_ringspread
	k0 OSClisten giOSC, "/diggainL", "f", gk_diggainL
	k0 OSClisten giOSC, "/diggainR", "f", gk_diggainR
	k0 OSClisten giOSC, "/feedback", "f", gk_feedback
	k0 OSClisten giOSC, "/feedbackwet", "f", gk_feedbackwet
	k0 OSClisten giOSC, "/stop", "i", kstop
	if( kstop == 1 ) then
		event "i", $End, 0, 0.1
	endif
	k0 OSClisten giOSC, "/testaudio", "i", ktestaudio
	if (ktestaudio != gk_testaudio_on) then
		if ( ktestaudio == 1 ) then
			event "i", $TestAudioOut, 0, 360000
			gk_testaudio_on = 1
		else
			turnoff2 $TestAudioOut, 0, 0.1
			gk_testaudio_on = 0
		endif
	endif

skip_osc_in:
	OSCsend ksendtrig, $ADDR_HOST, $ADDR_PORT, "/info", "fffffffffffff", \
				ksmoothfreq, gk_mix, gk_volpedal, gkV0, gkV1, gk_v0post, gk_v1post, \ 
				gk_vumasterL, gk_vumasterR, gk_vusource, gk_samplerate, gk_vuanalogL, \
				gk_vuanalogR
	gk_mastergain = port(ampdb(kmastergaindb) * (1-kmute), 0.05)	
endin

instr CalculateSpeed
	i_amptable ftgen 0, 0, -1001, 7,   0, 1, 0, 4, 0.001, 11, 0.063095734448, 4, 1, 980, 1
	iperdur = ksmps/sr
	kzeros0, kperiods, kfreq0_raw, kfreq1_raw init 0
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
	
	kzero0 trigger kv0, kthresh0, 2   ; 0=raising, 1=falling, 2=both
	kzero1 trigger kv1, kthresh1, 2  ; 0=raising, 1=falling, 2=both

	kismoving0 = ((kmax0 - kmin0) > kminvariation) ? 1 : 0
	kismoving1 = ((kmax1 - kmin1) > kminvariation) ? 1 : 0

	kzeros0 += (kismoving0 * kzero0)
	kzeros1 += (kismoving1 * kzero1)
	
	if ((kperiods % k_speedwindow_ks) == 0) then
		kfreq0_raw = kzeros0 / k_speedwindow
		kfreq1_raw = kzeros1 / k_speedwindow
		kzeros0 = 0
		kzeros1 = 0
		;;kperiods = 0
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
	aup = (amod1 - amod2) * 0.7
	adown = (amod1 + amod2) * 0.7
	xout aup, adown
endop
		
opcode lforange, k, kkki
	kfreq, kmin, kmax, imode xin
	kout lfo kmax-kmin, kfreq, imode
	kout += (kmax+kmin) * 0.5
	xout kout
endop
		
instr Audio
	iosctab ftgen 0, 0, 1000, -27, 0, 0, 2, 0, 16, 0.01, 30, 1, 400, 1
	
	;; --- SOURCE ---
	ksourcegain = port(gk_volpedal, 0.02)
	aSource = inch($FROM_SOURCE) * ksourcegain
	aMoireL   inch $FROM_MOIRE1
	aMoireR   inch $FROM_MOIRE2   
	
	;; --- ANALOG ---
	kgainanalog = gk_gain_analog * gk_volpedal
	aAnaL = aMoireL * kgainanalog
	aAnaR = aMoireR * kgainanalog
	gk_vuanalogL = rms(aAnaL)
	gk_vuanalogR = rms(aAnaR)
	
	;; --- DIGITAL ---
	aDigL = aSource * interp(gk_v0post)
	aDigR = aSource * interp(gk_v1post)
	
	;; --- RINGMOD BOOST ---
	kringfreq = port(gk_freq*gk_freqmult, 0.005)
	koscamp = port(tablei(kringfreq, iosctab), 0.005)
	;; aOsc oscili koscamp, kringfreq
	 
	;; --- OUT ---
	aOutL = aAnaL*(1-gk_mix)
	aOutL += aDigL*gk_mix   
	aOutL *= gk_mastergain
	
	aOutR = aAnaR*(1-gk_mix)
	aOutR += aDigR*gk_mix
	aOutR *= gk_mastergain
	
	/*
	aOsc *= gk_ringmod
	aRingL = aOutL*aOsc
	aRingR = aOutR*aOsc
	*/
 
	aup, adown freqshift aOutL, kringfreq, 1
	aRingL = (aup*gk_ringspread+adown*(1-gk_ringspread))*(koscamp*gk_ringmod)
	aup, adown freqshift aOutR, kringfreq, 1
	aRingR = (aup*(1-gk_ringspread)+adown*gk_ringspread)*(koscamp*gk_ringmod)
	
	aOutL = aOutL * (1-gk_ringmod) + aRingL
	aOutR = aOutR * (1-gk_ringmod) + aRingR
	
	/*
	aOutL, aOutR pconvolve aOutL*0.2, "/Users/rt/Audio/IR/experimental/metal_grid.aif", 512
	*/
	;aWetL0, aWetL1 babo aOutL*0.2, lforange(0.5, 0.1, 2.7, 0), 0, 0, 2.7, 1.1, 1.17, 0.95
	;aWetR0, aWetR1 babo aOutR*0.2	, lforange(0.4, 0.1, 2.7, 0), 2, 2, 2.7, 1.1, 1.17, 0.95
	aWetL0, aWetL1 babo aOutL * gk_feedback, 0, lforange(0.3, 0.2, 1.0, 0), 0, 2.7, 1.1, 1.17, 0.95
	aWetR0, aWetR1 babo aOutR * gk_feedback, lforange(0.4, 0.1, 2.7, 0), 2, 2, 2.7, 1.1, 1.17, 0.95

	aOutL = aWetL0*gk_feedbackwet + aOutL*(1-gk_feedbackwet)
	aOutR = aWetR0*gk_feedbackwet + aOutR*(1-gk_feedbackwet)
			
	; kmetro = metro($UIUPDATERATE)
	;gk_vumasterL = max_k(abs(aOutL), kmetro, 4)
	;gk_vumasterR = max_k(abs(aOutR), kmetro, 4)
	gk_vumasterL = rms(aOutL)
	gk_vumasterR = rms(aOutL)
	
	;; gk_dbL = dbamp(gk_vumasterL)
	;; gk_dbR = dbamp(gk_vumasterR)
	gk_vusource = rms(aSource)
	outch 1, aOutL
	outch 2, aOutR
endin

instr $TestAudioOut
	asigL oscili 0.5, 440
	asigR oscili 0.5, 263
	outch 1, asigL
	outch 2, asigR
endin

instr $End
	serialEnd giSerial
	event "e", 0, 0, 0.1 
endin

</CsInstruments>

<CsScore>

i "ReadSerial" 0 36000
i "CalculateSpeed" 0 36000
i "Brain" 0 36000
i "Audio" 1 36000
i "FlushSerialRegularly" 1 36000
i "UI_osc" 0 36000
i 2 0 0.1 32000 1; flush this number of characters at the beginning of the performance
; f 0 36000 
e 
</CsScore>

