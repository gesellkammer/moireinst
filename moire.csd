<CsoundSynthesizer>
<CsOptions>
-b1024   
-B2048
// OSX
// --omacro:ARDUINO=/dev/tty.usbmodemfd111
// --omacro:ARDUINO=/dev/tty.usbmodem1a21
--omacro:ARDUINO=/dev/tty.usbmodem1d11

;; Linux
;--omacro:ARDUINO=/dev/arduinoleo
</CsOptions>
<CsInstruments>

// ksmps  = 16   // this equals a control samplerate of 2600 Hz at 44100
ksmps  = 32      // this equals a control samplerate of 1300 Hz at 44100
nchnls = 4
0dbfs  = 1
sr     = 44100

;; ---------- CONFIG ----------

; audio channels
#define FROM_SOURCE #3#              
#define FROM_MOIRE1 #1#
#define FROM_MOIRE2 #2#                

#define ADDR_HOST #"127.0.0.1"#
#define ADDR_PORT #30019#
#define OSCPORT   #30018#
#define ADAPTPERIODX #12#
#define UIUPDATERATE #16#

#define FLUSHSERIALRATE #0.2#
#define FLUSHSERIAL_NUMCHARS #100#

#define USE_OUTPUT_LIMITER #1#

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
gk_vusource_prefader init 0
gk_max0, gk_max1 init 0
gk_min0, gk_min1 init 0
gk_shiftbw       init 8
gk_shiftwet      init 1
gk_phasewet      init 0.6
gk_gainanalogpost init 0
gk_volpedal_overdrive init 0
 
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
	// GEN27: linear bpf
	itab_pedal ftgen 0, 0, -1024, -27, 0, 0, 400, ampdb(-12), 680, ampdb(-3), 780, 1, 1000, 1, 1020, 1
	
	k_fader1 init 0
	k_pedal1 init 0
	k_counter init 0
	kVal = serialRead(giSerial)
	k_lasttime init 0
	k_samplerate init 0

	k0 = limit((k_fader1 - 0.03)/0.92, 0, 1)
	gk_mix = port(k0, 0.001)    
	k0 = limit((k_pedal1 - 0.02)/0.99, 0, 1)
	gk_volpedal = tablei(k0*1000, itab_pedal)
	gk_volpedal_overdrive = k0 < 0.85 ? 0 : (k0 - 0.85) / 0.14
	// gk_volpedal = port(pow(k0, gk_volcurve), 0.001)
 
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
	k0 OSClisten giOSC, "/shiftwet", "f", gk_shiftwet
	k0 OSClisten giOSC, "/phasewet", "f", gk_phasewet
	k0 OSClisten giOSC, "/gainanalogpost", "f", gk_gainanalogpost
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
	OSCsend ksendtrig, $ADDR_HOST, $ADDR_PORT, "/info", "ffffffffffffff", \
				ksmoothfreq, gk_mix, gk_volpedal, gkV0, gkV1, gk_v0post, gk_v1post, \ 
				gk_vumasterL, gk_vumasterR, gk_vusource, gk_samplerate, gk_vuanalogL, \
				gk_vuanalogR, gk_vusource_prefader
	gk_mastergain = port(ampdb(kmastergaindb) * (1-kmute), 0.05)	
endin

;; --------------------------------------------------------------
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
	aup = (amod1 - amod2) * 0.7
	adown = (amod1 + amod2) * 0.7
	xout aup, adown
endop

opcode freqshift1, a, ak
	ain, kdeltafreq xin
	areal, aimag hilbert ain
	asin oscili 1, kdeltafreq, gi_sinetable
	acos oscili 1, kdeltafreq, gi_sinetable, 0.25
	amod1 = areal*acos
	amod2 = aimag*asin
	kwhich = port(kdeltafreq >= 0 ? 1 : 0, 0.01)
	aup = amod1 - amod2
	adown = amod1 + amod2
	aout ntrpol adown, aup, kwhich
	xout aout
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
	krvt = -4.605170185988091 * kdel / log(kfback)
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

;; --------------------------------------------------------------
instr Audio
	kuimetro = metro($UIUPDATERATE)
	
	;; --- CURVES ---
	itab_speed2ringenv ftgen 0, 0, -513, -27, 0,0,   2,0,  16,0.01,  30,1,  400,1
	itab_speed2fback   ftgen 0, 0, -513, -27, 0,0.85, 4,0.9, 16,0.93, 50,0.93, 150,0.97, 200,0.99, 250, 0.99, 400,0.9999
	itab_sourceamp2fbackmult ftgen 0, 0, -200, -27, 0, 1, 80, 1, 90, 1.01, 100, 1.02
	
	;; --- SOURCE ---
	aSource inch $FROM_SOURCE
	ksourcegain = port(gk_volpedal, 0.025)
	
	gk_vusource_prefader = max_k(aSource, kuimetro, 1)
	aSource *= interp(ksourcegain)
	aMoireL   inch $FROM_MOIRE1
	aMoireR   inch $FROM_MOIRE2
	
	ksourceampdb  = 90 - rms(aSource)
	
	;; --- ANALOG ---
	kgainanalog = gk_gain_analog * ksourcegain
	aAnaL = aMoireL * kgainanalog
	aAnaR = aMoireR * kgainanalog
	kgate0db = 96 + dbamp(gk_gate0)
	kgate1db = 96 + dbamp(gk_gate1)
	
	;; -- TODO : analog gate
	
	gk_vuanalogL = max_k(aAnaL, kuimetro, 1)
	gk_vuanalogR = max_k(aAnaR, kuimetro, 1)

	;; denormalize
	denorm aSource, aAnaL, aAnaR
	
	;; --- FREQSHIFT --- 
	aDigL = aSource
	irandbw = 0.4
	kshiftbw = gk_shiftbw * (1-irandbw*0.5+randi(irandbw, 5))
	kdeltafreq = port(scale((gk_v1post - gk_v0post), kshiftbw, 0.25), 0.01)
	ashiftR = freqshift1(aSource, kdeltafreq)
	aDigR = ntrpol(aSource, ashiftR, gk_shiftwet)

	; --- comb ---
	kdelL = 0.01  + gk_v0post * 0.0023
	kdelR = 0.005 + gk_v1post * 0.0023
	
	kfback = tablei(gk_freq, itab_speed2fback)*tablei(ksourceampdb, itab_sourceamp2fbackmult)
	
	aphL  = fbcomb(aDigL, kfback, kdelL)   // fbcomb(ain, kfback, kdel)
	aDigL = ntrpol(aDigL, aphL, gk_phasewet) * gk_v0post

	aphR  = fbcomb(aDigR, kfback, kdelR)
	aDigR = ntrpol(aDigR, aphR, gk_phasewet) * gk_v1post
	
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
	
	aOutL = ntrpol(aOutL, aRingL, gk_ringmod)
	aOutR = ntrpol(aOutR, aRingR, gk_ringmod)
	
	; ---- control feedback resonance ---- 
	aOutM = (aOutL+aOutR)*0.70710678117
	kamp = pow(max_k(aOutM, metro(20), 1), 2)
	kspeedindex = pow(limit(gk_freq/150, 0, 1), 0.5)
	kfdn_cutoff   = port(scale(kamp, 12000, 4000), 0.005)
	kfdn_freq     = port(scale(kspeedindex, 0.3, 0.1), 0.01)
	kfdn_pitchmod = port(scale(kspeedindex, 0.5, 0.05), 0.005)
	
	// fdn(ain, kgain, kdelaytime, kcutoff, kfreq, kpitchmod, i_tapmix, i_delratio, i_delmin, i_delmax, i_cutoffdev) : a
	aWetL = fdn(aOutL, gk_feedback, 0.15, kfdn_cutoff, kfdn_freq, kfdn_pitchmod, 0.3, 1, 0.063, 0.091)
	aWetR = fdn(aOutR, gk_feedback, 0.15, kfdn_cutoff, kfdn_freq, kfdn_pitchmod, 0.3, 1, 0.063, 0.091)

	aOutL ntrpol aOutL, aWetL, gk_feedbackwet
	aOutR ntrpol aOutR, aWetR, gk_feedbackwet
	aOutL *= interp(gk_mastergain)
	aOutR *= interp(gk_mastergain)

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
i 2 0 0.1 32000 1  // flush this number of characters at the beginning of the performance
e 
</CsScore>
</CsoundSynthesizer>