<CsoundSynthesizer>
<CsOptions>
;-b1024
;-B1536
;; OSX
;--omacro:ARDUINO=/dev/tty.usbmodemfd111
;--omacro:ARDUINO=/dev/tty.usbmodem1a21
;--omacro:ARDUINO=/dev/tty.usbmodem1d11

;; Linux
--omacro:ARDUINO=/dev/arduinoleo
</CsOptions>
<CsInstruments>

;ksmps  = 16   ; this equals a control samplerate of 2600 Hz at 44100
ksmps  = 32   ; this equals a control samplerate of 1300 Hz at 44100
nchnls = 4
0dbfs  = 1
sr     = 44100

#define FROM_SOURCE #1#              
#define FROM_MOIRE1 #4#
#define FROM_MOIRE2 #3#                

#define ADDR_HOST #"127.0.0.1"#
#define ADDR_PORT #30019#
#define OSCPORT   #30018#
#define ADAPTPERIODX #12#
#define UIUPDATERATE #12#
#define USE_OSC ##
#define SERIALOSC ##

#ifndef ARDUINO
	#ifdef DARWIN
		#define ARDUINO #/dev/tty.usbmodem1a21#
	#endif
	#ifdef LINUX
		#define ARDUINO #/dev/arduinoleo#
	#endif
#endif
#ifndef ARDUINO
        #define ARDUINO #/dev/null#
#endif

;; ------ PRIVATE --------
#define SAW #1#

ga_source init 0
gkV0, gkV1, gk_freq, gk_v0post, gk_v1post, gk_volpedal init 0

gk_dbL, gk_dbR init -120
gk_speedwindow  init 0.030
gk_minvariation init 0.1
gk_smooth       init 0.005
gk_mastergain   init 1
gk_mastermute   init 0
gk_stereomagnify init 1
gk_gate0 init ampdb(-40)
gk_gate1 init ampdb(-24)
gk_samplerate init -1
gk_vusource init 0
gk_vumasterL init 0
gk_vumasterR init 0
gk_volcurve init 1

#ifndef SERIALOSC
giSerial serialBegin "$ARDUINO", 115200
alwayson "ReadSerial"
#endif

#ifdef SERIALOSC
alwayson "ReadSerialOSC"
#endif

alwayson "CalculateSpeed"
alwayson "Brain"
alwayson "Audio"

giOSC OSCinit $OSCPORT

#ifdef USE_OSC
alwayson "UI_osc"
#else
alwayson "UI_qt"
#endif

/*
instr 1
    serialFlush giSerial   
endin
*/

instr ReadSerialOSC
	kv0, kv1, kfader1, kpedal1 init 0
	ksamplerate init -1
	
	k0 OSClisten giOSC, "/data", "ii", kv0, kv1
	if (k0 == 1) then
		gkV0 = kv0/1023
		gkV1 = kv1/1023
	endif
	
	k0 OSClisten giOSC, "/ctrl", "iii", kfader1, kpedal1, ksamplerate
	
	gk_mix = port(limit((kfader1/1023-0.03)/0.92, 0, 1), 0.003)
	kpedal1lim = limit((kpedal1/1023 - 0.02)/0.96, 0, 1)
    gk_volpedal = port(pow(kpedal1lim, gk_volcurve), 0.001)
    if (k0 == 1) then
    		gk_samplerate = ksamplerate
    	endif
endin

/*
instr ReadSerial
    k_fader1 init 0
    k_pedal1 init 0
    k_counter init 0
    kVal = serialRead(giSerial)
    k_lasttime init 0
    k_samplerate init 0
   
    if (kVal < 128) kgoto exit
    if( kVal < 140 ) then   
        k0  = serialRead(giSerial)
        k0 *= 128
        k0 += serialRead(giSerial)
        gkV0 = k0/1023
        k0  = serialRead(giSerial)
        k0 *= 128
        k0 += serialRead(giSerial)
        gkV1 = k0/1023
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
    k0 = limit((k_fader1 - 0.03)/0.92, 0, 1)
    gk_mix = port(k0, 0.003)    
    k0 = limit((k_pedal1 - 0.02)/0.96, 0, 1)
    gk_volpedal = port(pow(k0, gk_volcurve), 0.001)
endin
*/

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
    k0 gate3lin k0, gk_gate0, gk_gate1, gk_gate0
    k1 gate3lin k1, gk_gate0, gk_gate1, gk_gate0
    gk_v0post = k0
    gk_v1post = k1
endin

opcode osclisteni, k, Sk
	Spath, kdefault xin
	k1 init 0
	k0 OSClisten giOSC, Spath, "i", k1
	kout = k0 == 1 ? k1 : kdefault
	xout kout
endop

opcode osclistenf, k, Sk
	Spath, kdefault xin
	k0 OSClisten giOSC, Spath, "f", kdefault
	xout kdefault
endop

instr UI_osc
	iperdur = ksmps/sr
	imaxcounter = int(1/$UIUPDATERATE / iperdur)
	kcounter init 0
	kspeedperiod init 50
	ksmooth init 7
	kstereomagnify init 1
	kmastergaindb init 0
	kmute init 0
	kgate0db init -40
	kgate1db init -20
	kringmodboost init 1
	kstop init 0
	kcounter += 1
    ksmoothfreq = port(gk_freq, 1/$UIUPDATERATE)

	if (kcounter > imaxcounter ) then
		kspeedperiod = osclisteni("/speedperiod_ms", kspeedperiod)
		gk_speedwindow = kspeedperiod/1000
		gk_minvariation = osclistenf("/minvariation", gk_minvariation)
		ksmooth = osclisteni("/smooth_ms", ksmooth)
		gk_smooth = ksmooth/1000
		kstereomagnify = osclistenf("/stereomagnify", kstereomagnify)
		gk_stereomagnify = kstereomagnify
		kmastergaindb = osclistenf("/mastergaindb", kmastergaindb)
		kmute = osclisteni("/mastermute", kmute)
		gk_volcurve = osclistenf("/volcurve", gk_volcurve)
		k0 OSClisten giOSC, "/gate0db", "f", kgate0db
		;; kgate0db = osclistenf("/gate0db", kgate0db)
		gk_gate0 = ampdb(kgate0db)
		kgate1db = osclistenf("/gate0db", kgate1db)
		gk_gate1 = ampdb(kgate1db)
		kringmodboost = osclisteni("/ringmodboost", kringmodboost)
		kstop = osclisteni("/stop", kstop)
		;; kstop OSClisten giOSC, "/stop", "i", kstop
		if( kstop == 1 ) then
			event "e", 0, 0, 0.1 
		endif
		gk_ringmod = kringmodboost/100
	endif

	ksendtrig metro $UIUPDATERATE
	OSCsend ksendtrig, $ADDR_HOST, $ADDR_PORT, "/info", "fffffffffff", ksmoothfreq, gk_mix, gk_volpedal, gkV0, gkV1, gk_v0post, gk_v1post, gk_vumasterL, gk_vumasterR, gk_vusource, gk_samplerate
	gk_mastergain = port(ampdb(kmastergaindb) * (1-kmute), 0.05)	
endin

instr UI_qt
    iperdur = ksmps/sr
    imaxcounter = int(1/$UIUPDATERATE / iperdur)
    kcounter init 0
    kcounter += 1
    ksmoothfreq = port(gk_freq, 1/$UIUPDATERATE)
    if (kcounter > imaxcounter) then
        gk_speedwindow  = invalue("speedperiod_ms")/1000
        gk_minvariation = invalue("minvariation")
        gk_smooth = invalue("smooth_ms")/1000
        gk_stereomagnify = invalue("stereomagnify")
        kmastergain = invalue("mastergain")
        kmute = invalue("mastermute")   
        gk_gate0 = ampdb(invalue("gate0_db"))
        gk_gate1 = ampdb(invalue("gate1_db"))
        gk_ringmod = invalue("ringmod_percent")/100
        outvalue "freq", ksmoothfreq
        outvalue "mix", gk_mix
        outvalue "inputgain", dbamp(gk_volpedal)
        outvalue "v0", gkV0
        outvalue "v1", gkV1
        outvalue "v0post", gk_v0post
        outvalue "v1post", gk_v1post
        outvalue "avgpre_db", dbamp((gkV0+gkV1)*0.5)
        outvalue "avgpost_db", dbamp((gk_v0post + gk_v1post)*0.5)
        outvalue "dbout0", gk_dbL
        outvalue "dbout1", gk_dbR
        outvalue "samplerate", port(gk_samplerate, 0.003)
        kcounter = 0
    endif
    gk_mastergain = port(ampdb(kmastergain) * (1-kmute), 0.05)
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
    
    kminvariation = gk_minvariation.
    
    kv0 = gkV0
    kv1 = gkV1
    
    kmin0_new = min(kmin0_new, kv0)
    kmax0_new = max(kmax0_new, kv0)
    kmin1_new = min(kmin1_new, kv1)
    kmax1_new = max(kmax1_new, kv1)
    
    kthresh0 = (kmax0 + kmin0) * 0.5
    kthresh1 = (kmax1 + kmin1) * 0.5
    ;kthresh0 = kmin0 + (kmax0 - kmin0)*0.5
    ;kthresh1 = kmin1 + (kmax1 - kmin1)*0.5
    
    kzero0 trigger kv0, kthresh0, 2   ; 0=raising, 1=falling, 2=both
    kzero1 trigger kv1, kthresh1, 2  ; 0=raising, 1=falling, 2=both
    ;kzero0 = trigger(kv0, kmin0 + (kmax0 - kmin0)*0.6, 0) + trigger(kv0, kmin0 + (kmax0 - kmin0)*0.4, 1)
    ;kzero1 = trigger(kv0, kmin0 + (kmax0 - kmin0)*0.7, 0) + trigger(kv0, kmin0 + (kmax0 - kmin0)*0.3, 1)
    
    kthreshok0 = ((kmax0 - kmin0) > kminvariation) ? 1 : 0
    kthreshok1 = ((kmax1 - kmin1) > kminvariation) ? 1 : 0

    kzeros0 += kzero0*kthreshok0
    kzeros1 += kzero1*kthreshok1
    
    if (kperiods % k_speedwindow_ks == 0) then
        kfreq0_raw = kzeros0 / k_speedwindow
        kfreq1_raw = kzeros1 / k_speedwindow
        kzeros0 = 0
        kzeros1 = 0
    endif
    
    k_minmax_ks = k_speedwindow_ks * $ADAPTPERIODX
    if (kperiods % k_minmax_ks == 0) then
        kmin0 = (kmin0 + kmin0_new)*0.5
        kmin1 = (kmin1 + kmin1_new)*0.5
        kmax0 = (kmax0 + kmax0_new)*0.5
        kmax1 = (kmax1 + kmax1_new)*0.5
        kmin0_new = kv0
        kmin1_new = kv1
        kmax0_new = kv0
        kmax1_new = kv1
    endif   
    
    kfreq  = portk((kfreq0_raw+kfreq1_raw)*0.5, gk_smooth)
    gk_freq = kfreq
    kperiods = kperiods+1
endin

opcode linlin, k, kkkkk
    kx, kx0, kx1, ky0, ky1 xin
    kout = (kx - kx0)/(kx1-kx0)
    kout = ky0 + kout*(ky1-ky0)
    xout kout
endop

instr Audio
    iosctab ftgen 0, 0, 1000, -27, 0, 0, 2, 0.001, 8, 0.5, 20, 1, 400, 1
    aSource inch $FROM_SOURCE
    aMoireL inch $FROM_MOIRE1
    aMoireR inch $FROM_MOIRE2   
    
    aAnaL = aMoireL
    aAnaR = aMoireR
    
    av0 = interp(gk_v0post)
    av1 = interp(gk_v1post)
    
    aDigL = aSource * av0
    aDigR = aSource * av1
    
    aOsc oscili 1, port(gk_freq*5, 0.01)
    koscamp = port(tablei(gk_freq, iosctab), 0.01)
    
    aOsc *= koscamp
    
    aOutL = aAnaL*(1-gk_mix)
    aOutL += aDigL*gk_mix   
    aOutL *= gk_mastergain
    aOutR = aAnaR*(1-gk_mix)
    aOutR += aDigR*gk_mix
    aOutR *= gk_mastergain
    
    aOutL = aOutL * (1-gk_ringmod) + aOutL*aOsc * gk_ringmod
    aOutR = aOutR * (1-gk_ringmod) + aOutR*aOsc * gk_ringmod

    outch 1, aOutL
    outch 2, aOutR
    
    kmetro = metro($UIUPDATERATE)
    gk_vumasterL = max_k(abs(aOutL), kmetro, 4)
    gk_vumasterR = max_k(abs(aOutR), kmetro, 4)
    gk_dbL = dbamp(gk_vumasterL)
    gk_dbR = dbamp(gk_vumasterR)
    gk_vusource = max_k(abs(aSource), kmetro, 4)
endin


instr Debug
    printk 0.2, gkV0
    printk 0.2, gkV1
    printk 0.2, gk_freq
endin

</CsInstruments>
<CsScore>
; i 1 0 0.01 
f 0 36000 
e 
 
 
 
 
 </CsScore>


</CsoundSynthesizer>
<bsbPanel>
 <label>Widgets</label>
 <objectName/>
 <x>870</x>
 <y>1337</y>
 <width>583</width>
 <height>384</height>
 <visible>true</visible>
 <uuid/>
 <bgcolor mode="background">
  <r>255</r>
  <g>255</g>
  <b>255</b>
 </bgcolor>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>324</x>
  <y>317</y>
  <width>176</width>
  <height>32</height>
  <uuid>{fe34a705-42d2-492d-b356-44eeab7ec31e}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>RINGMOD BOOST  (%)</label>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>333</x>
  <y>155</y>
  <width>156</width>
  <height>30</height>
  <uuid>{4d96bc50-444c-4409-a921-394eae862a0f}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>MASTER GAIN (dB)</label>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>325</x>
  <y>9</y>
  <width>5</width>
  <height>258</height>
  <uuid>{6e361b85-cbba-456a-888a-af9c004f9ee8}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label/>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>12</fontsize>
  <precision>3</precision>
  <color>
   <r>223</r>
   <g>223</g>
   <b>223</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>border</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>8</x>
  <y>170</y>
  <width>314</width>
  <height>5</height>
  <uuid>{00a53fc4-612f-48b6-bcbc-6bbebb56b284}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>GATE</label>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>12</fontsize>
  <precision>3</precision>
  <color>
   <r>236</r>
   <g>236</g>
   <b>236</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>border</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBHSlider">
  <objectName>mix</objectName>
  <x>378</x>
  <y>77</y>
  <width>133</width>
  <height>20</height>
  <uuid>{470f1998-00ad-4dcc-b4f5-cd5eb9a68560}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <minimum>0.00000000</minimum>
  <maximum>1.00000000</maximum>
  <value>0.44021208</value>
  <mode>lin</mode>
  <mouseControl act="jump">continuous</mouseControl>
  <resolution>-1.00000000</resolution>
  <randomizable group="0">false</randomizable>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>speedperiod_ms</objectName>
  <x>235</x>
  <y>17</y>
  <width>44</width>
  <height>33</height>
  <uuid>{58ec7c50-4e35-4c37-bf16-cdfcf5f12a6b}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>left</alignment>
  <font>DejaVu Sans</font>
  <fontsize>24</fontsize>
  <color>
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <value>45.00000000</value>
  <resolution>1.00000000</resolution>
  <minimum>1.00000000</minimum>
  <maximum>120.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>mastergain</objectName>
  <x>493</x>
  <y>154</y>
  <width>43</width>
  <height>31</height>
  <uuid>{c21f5bdf-0fe1-404a-9fd8-64f3fc2900eb}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>right</alignment>
  <font>DejaVu Sans</font>
  <fontsize>24</fontsize>
  <color>
   <r>65</r>
   <g>208</g>
   <b>246</b>
  </color>
  <bgcolor mode="nobackground">
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </bgcolor>
  <value>-39.00000000</value>
  <resolution>1.00000000</resolution>
  <minimum>-90.00000000</minimum>
  <maximum>0.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>14</x>
  <y>17</y>
  <width>214</width>
  <height>27</height>
  <uuid>{c61f09d9-9598-4ae3-bb42-ab122951b882}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>SPEED ANALYSIS WINDOW</label>
  <alignment>right</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>279</x>
  <y>17</y>
  <width>33</width>
  <height>29</height>
  <uuid>{f6dabd51-2614-450c-a107-010d82963e9f}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>ms</label>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>113</x>
  <y>53</y>
  <width>115</width>
  <height>28</height>
  <uuid>{36d35cc8-dab9-4ea5-a9f9-47ccc95fd1f4}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>SMOOTHING</label>
  <alignment>right</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>smooth_ms</objectName>
  <x>235</x>
  <y>52</y>
  <width>44</width>
  <height>33</height>
  <uuid>{68683c52-e679-422f-89d1-eba383b362c7}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>left</alignment>
  <font>DejaVu Sans</font>
  <fontsize>24</fontsize>
  <color>
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <value>8.00000000</value>
  <resolution>1.00000000</resolution>
  <minimum>1.00000000</minimum>
  <maximum>120.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>74</x>
  <y>86</y>
  <width>154</width>
  <height>31</height>
  <uuid>{e039a4f6-5950-4978-abb3-014cafae1f13}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>MIN. VARIATION</label>
  <alignment>right</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>minvariation</objectName>
  <x>235</x>
  <y>88</y>
  <width>49</width>
  <height>30</height>
  <uuid>{194d08be-e409-4ae4-bb8b-4609bbe902f9}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>left</alignment>
  <font>DejaVu Sans</font>
  <fontsize>24</fontsize>
  <color>
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <value>0.41000000</value>
  <resolution>0.01000000</resolution>
  <minimum>0.00000000</minimum>
  <maximum>1.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>328</x>
  <y>73</y>
  <width>48</width>
  <height>31</height>
  <uuid>{1430ac9e-6257-4392-b423-c107bc0fc49f}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>ANA</label>
  <alignment>right</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>517</x>
  <y>72</y>
  <width>39</width>
  <height>29</height>
  <uuid>{9c6c15fa-6313-4ae8-8eef-c0c86b688b05}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>DIG</label>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>44</x>
  <y>129</y>
  <width>184</width>
  <height>31</height>
  <uuid>{409b5fac-88cc-490a-a1ff-6907e0b58f21}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>CALCULATED SPEED</label>
  <alignment>right</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>mastermute</objectName>
  <x>516</x>
  <y>186</y>
  <width>20</width>
  <height>30</height>
  <uuid>{bd71f9b0-3708-4474-9968-a1f8348c1624}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>center</alignment>
  <font>Helvetica Neue</font>
  <fontsize>24</fontsize>
  <color>
   <r>65</r>
   <g>208</g>
   <b>246</b>
  </color>
  <bgcolor mode="nobackground">
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </bgcolor>
  <value>0.00000000</value>
  <resolution>1.00000000</resolution>
  <minimum>0.00000000</minimum>
  <maximum>1.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>426</x>
  <y>185</y>
  <width>56</width>
  <height>29</height>
  <uuid>{04ab2e75-0f15-41ff-99ec-3ad467517b59}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>MUTE</label>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>freq</objectName>
  <x>235</x>
  <y>130</y>
  <width>50</width>
  <height>29</height>
  <uuid>{b1607e50-b403-4385-9027-440113220c99}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>24</fontsize>
  <color>
   <r>69</r>
   <g>69</g>
   <b>69</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <value>0.00000000</value>
  <resolution>1.00000000</resolution>
  <minimum>-999999999999.00000000</minimum>
  <maximum>999999999999.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject version="2" type="BSBController">
  <objectName>v0</objectName>
  <x>42</x>
  <y>277</y>
  <width>196</width>
  <height>9</height>
  <uuid>{b5cfa0cc-1908-4260-a243-82723e2c9d7f}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <objectName2>v0</objectName2>
  <xMin>0.00000000</xMin>
  <xMax>1.00000000</xMax>
  <yMin>0.00000000</yMin>
  <yMax>1.00000000</yMax>
  <xValue>0.28739003</xValue>
  <yValue>0.28739003</yValue>
  <type>fill</type>
  <pointsize>1</pointsize>
  <fadeSpeed>0.00000000</fadeSpeed>
  <mouseControl act="press">jump</mouseControl>
  <color>
   <r>36</r>
   <g>169</g>
   <b>225</b>
  </color>
  <randomizable mode="both" group="0">false</randomizable>
  <bgcolor>
   <r>0</r>
   <g>0</g>
   <b>0</b>
  </bgcolor>
 </bsbObject>
 <bsbObject version="2" type="BSBController">
  <objectName>v1</objectName>
  <x>42</x>
  <y>289</y>
  <width>196</width>
  <height>9</height>
  <uuid>{ca277370-0c5c-4238-b455-695aa68553f6}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <objectName2/>
  <xMin>0.00000000</xMin>
  <xMax>1.00000000</xMax>
  <yMin>0.00000000</yMin>
  <yMax>1.00000000</yMax>
  <xValue>0.14858260</xValue>
  <yValue>0.36697248</yValue>
  <type>fill</type>
  <pointsize>1</pointsize>
  <fadeSpeed>0.00000000</fadeSpeed>
  <mouseControl act="press">jump</mouseControl>
  <color>
   <r>36</r>
   <g>169</g>
   <b>225</b>
  </color>
  <randomizable mode="both" group="0">false</randomizable>
  <bgcolor>
   <r>0</r>
   <g>0</g>
   <b>0</b>
  </bgcolor>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>324</x>
  <y>281</y>
  <width>168</width>
  <height>29</height>
  <uuid>{fe5b85a0-9ac9-4e5b-ba6d-bb1d773aee82}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>STEREO MAGNIFY (X)</label>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>stereomagnify</objectName>
  <x>513</x>
  <y>282</y>
  <width>35</width>
  <height>31</height>
  <uuid>{1eec8b02-684d-49e6-a0c2-f7995ab6f9e6}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>left</alignment>
  <font>DejaVu Sans</font>
  <fontsize>24</fontsize>
  <color>
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <value>2.50000000</value>
  <resolution>0.10000000</resolution>
  <minimum>0.00000000</minimum>
  <maximum>10.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>0</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>279</x>
  <y>52</y>
  <width>33</width>
  <height>29</height>
  <uuid>{4a30570f-be00-4262-b43a-7c138ddf70a1}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>ms</label>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBController">
  <objectName>v0post</objectName>
  <x>42</x>
  <y>306</y>
  <width>196</width>
  <height>9</height>
  <uuid>{e9c67402-192e-4ea3-aa60-7bd533e349bb}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <objectName2/>
  <xMin>0.00000000</xMin>
  <xMax>1.00000000</xMax>
  <yMin>0.00000000</yMin>
  <yMax>1.00000000</yMax>
  <xValue>0.32768607</xValue>
  <yValue>0.01270772</yValue>
  <type>fill</type>
  <pointsize>1</pointsize>
  <fadeSpeed>0.00000000</fadeSpeed>
  <mouseControl act="press">jump</mouseControl>
  <color>
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </color>
  <randomizable mode="both" group="0">false</randomizable>
  <bgcolor>
   <r>0</r>
   <g>0</g>
   <b>0</b>
  </bgcolor>
 </bsbObject>
 <bsbObject version="2" type="BSBController">
  <objectName>v1post</objectName>
  <x>42</x>
  <y>318</y>
  <width>196</width>
  <height>9</height>
  <uuid>{0b7aa097-60ac-4b99-9d6d-cd6f1b2d7cac}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <objectName2/>
  <xMin>0.00000000</xMin>
  <xMax>1.00000000</xMax>
  <yMin>0.00000000</yMin>
  <yMax>1.00000000</yMax>
  <xValue>0.00231509</xValue>
  <yValue>0.36697248</yValue>
  <type>fill</type>
  <pointsize>1</pointsize>
  <fadeSpeed>0.00000000</fadeSpeed>
  <mouseControl act="press">jump</mouseControl>
  <color>
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </color>
  <randomizable mode="both" group="0">false</randomizable>
  <bgcolor>
   <r>0</r>
   <g>0</g>
   <b>0</b>
  </bgcolor>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>avgpre_db</objectName>
  <x>246</x>
  <y>273</y>
  <width>29</width>
  <height>29</height>
  <uuid>{e185bd88-bcff-4ca5-b98c-7071b3f04c23}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <color>
   <r>69</r>
   <g>69</g>
   <b>69</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <value>-13.23141595</value>
  <resolution>1.00000000</resolution>
  <minimum>-999999999999.00000000</minimum>
  <maximum>999999999999.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>avgpost_db</objectName>
  <x>246</x>
  <y>303</y>
  <width>29</width>
  <height>29</height>
  <uuid>{d3b6fe4c-1a12-4969-a14e-610e6db1da65}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <color>
   <r>69</r>
   <g>69</g>
   <b>69</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <value>-15.65029118</value>
  <resolution>1.00000000</resolution>
  <minimum>-999999999999.00000000</minimum>
  <maximum>999999999999.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>91</x>
  <y>220</y>
  <width>75</width>
  <height>32</height>
  <uuid>{c826313a-ddf7-4c41-b839-7925bf7e1d7e}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>THRESH</label>
  <alignment>right</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>gate1_db</objectName>
  <x>164</x>
  <y>220</y>
  <width>71</width>
  <height>31</height>
  <uuid>{bc9b8b95-1efe-4ff3-aee3-594aac385d01}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>center</alignment>
  <font>Helvetica Neue</font>
  <fontsize>24</fontsize>
  <color>
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <value>-20.00000000</value>
  <resolution>1.00000000</resolution>
  <minimum>-60.00000000</minimum>
  <maximum>-6.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>234</x>
  <y>221</y>
  <width>33</width>
  <height>28</height>
  <uuid>{2c70711e-ebb2-416f-b133-238d8b23bef1}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>dB</label>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>276</x>
  <y>277</y>
  <width>24</width>
  <height>23</height>
  <uuid>{708d8402-689e-43b7-8dbd-942d480bd90f}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>dB</label>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>10</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>276</x>
  <y>307</y>
  <width>24</width>
  <height>23</height>
  <uuid>{ece93e61-9f47-48c5-9e1d-ee866356f243}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>dB</label>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>10</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>113</x>
  <y>183</y>
  <width>53</width>
  <height>32</height>
  <uuid>{18b0e5d2-a48a-44c9-a7ca-6f18a92adb76}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>-90db</label>
  <alignment>right</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>gate0_db</objectName>
  <x>165</x>
  <y>183</y>
  <width>71</width>
  <height>31</height>
  <uuid>{e6750454-3277-4c65-9790-ae3e1f99050a}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>center</alignment>
  <font>Helvetica Neue</font>
  <fontsize>24</fontsize>
  <color>
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <value>-45.00000000</value>
  <resolution>1.00000000</resolution>
  <minimum>-90.00000000</minimum>
  <maximum>-24.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>235</x>
  <y>184</y>
  <width>33</width>
  <height>28</height>
  <uuid>{fe8e1b34-22b8-4cb9-9403-188300e5ea83}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>dB</label>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBController">
  <objectName>dbout0</objectName>
  <x>338</x>
  <y>132</y>
  <width>123</width>
  <height>7</height>
  <uuid>{6b1529d3-94d7-4aff-b1e2-3404c193e56d}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <objectName2/>
  <xMin>-40.00000000</xMin>
  <xMax>6.00000000</xMax>
  <yMin>0.00000000</yMin>
  <yMax>1.00000000</yMax>
  <xValue>-130.57847627</xValue>
  <yValue>0.01270772</yValue>
  <type>fill</type>
  <pointsize>1</pointsize>
  <fadeSpeed>0.00000000</fadeSpeed>
  <mouseControl act="press">jump</mouseControl>
  <color>
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </color>
  <randomizable mode="both" group="0">false</randomizable>
  <bgcolor>
   <r>0</r>
   <g>0</g>
   <b>0</b>
  </bgcolor>
 </bsbObject>
 <bsbObject version="2" type="BSBController">
  <objectName>dbout1</objectName>
  <x>338</x>
  <y>140</y>
  <width>123</width>
  <height>7</height>
  <uuid>{06b7f4ea-4929-4438-8614-bf7828a07886}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <objectName2/>
  <xMin>-40.00000000</xMin>
  <xMax>6.00000000</xMax>
  <yMin>0.00000000</yMin>
  <yMax>1.00000000</yMax>
  <xValue>-145.69859444</xValue>
  <yValue>0.36697248</yValue>
  <type>fill</type>
  <pointsize>1</pointsize>
  <fadeSpeed>0.00000000</fadeSpeed>
  <mouseControl act="press">jump</mouseControl>
  <color>
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </color>
  <randomizable mode="both" group="0">false</randomizable>
  <bgcolor>
   <r>0</r>
   <g>0</g>
   <b>0</b>
  </bgcolor>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>ringmod_percent</objectName>
  <x>504</x>
  <y>316</y>
  <width>44</width>
  <height>33</height>
  <uuid>{cdd0228c-603b-42da-a96e-09d59431303f}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>right</alignment>
  <font>Helvetica Neue</font>
  <fontsize>24</fontsize>
  <color>
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <value>0.00000000</value>
  <resolution>1.00000000</resolution>
  <minimum>0.00000000</minimum>
  <maximum>100.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>333</x>
  <y>27</y>
  <width>137</width>
  <height>30</height>
  <uuid>{cc751987-a262-4699-b8cb-759ad62293a4}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>INPUT GAIN  (dB)</label>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBController">
  <objectName>in_vu</objectName>
  <x>337</x>
  <y>16</y>
  <width>125</width>
  <height>7</height>
  <uuid>{ea6a70ab-314f-42de-ae26-3497765ff20c}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <objectName2/>
  <xMin>-80.00000000</xMin>
  <xMax>0.00000000</xMax>
  <yMin>0.00000000</yMin>
  <yMax>1.00000000</yMax>
  <xValue>-36.64583245</xValue>
  <yValue>0.01270772</yValue>
  <type>fill</type>
  <pointsize>1</pointsize>
  <fadeSpeed>0.00000000</fadeSpeed>
  <mouseControl act="press">jump</mouseControl>
  <color>
   <r>255</r>
   <g>177</g>
   <b>0</b>
  </color>
  <randomizable mode="both" group="0">false</randomizable>
  <bgcolor>
   <r>0</r>
   <g>0</g>
   <b>0</b>
  </bgcolor>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>inputgain</objectName>
  <x>501</x>
  <y>27</y>
  <width>55</width>
  <height>30</height>
  <uuid>{55b70108-641f-435f-b94b-0dfd17d70b82}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>left</alignment>
  <font>DejaVu Sans</font>
  <fontsize>24</fontsize>
  <color>
   <r>69</r>
   <g>69</g>
   <b>69</b>
  </color>
  <bgcolor mode="nobackground">
   <r>68</r>
   <g>216</g>
   <b>255</b>
  </bgcolor>
  <value>-2.54631056</value>
  <resolution>0.10000000</resolution>
  <minimum>-90.00000000</minimum>
  <maximum>0.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject version="2" type="BSBLabel">
  <objectName/>
  <x>138</x>
  <y>363</y>
  <width>82</width>
  <height>23</height>
  <uuid>{61eff695-e43f-4b63-8388-48c8f955c82e}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <label>SAMPLERATE</label>
  <alignment>right</alignment>
  <font>Helvetica Neue</font>
  <fontsize>10</fontsize>
  <precision>3</precision>
  <color>
   <r>145</r>
   <g>145</g>
   <b>145</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
 </bsbObject>
 <bsbObject version="2" type="BSBScrollNumber">
  <objectName>samplerate</objectName>
  <x>224</x>
  <y>363</y>
  <width>50</width>
  <height>23</height>
  <uuid>{ae73f064-4fb3-47e4-8f5c-32af58f16769}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <alignment>left</alignment>
  <font>Helvetica Neue</font>
  <fontsize>12</fontsize>
  <color>
   <r>69</r>
   <g>69</g>
   <b>69</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <value>1259.86461696</value>
  <resolution>1.00000000</resolution>
  <minimum>-999999999999.00000000</minimum>
  <maximum>999999999999.00000000</maximum>
  <bordermode>noborder</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>1</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
</bsbPanel>
<bsbPresets>
</bsbPresets>
