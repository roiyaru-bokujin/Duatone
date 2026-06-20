Engine_Duatone : CroneEngine {
	var left;
	var right;

	voiceFor { arg which;
		^if(which == 1) { left } { right }
	}

	alloc {
		SynthDef("DuatoneVoice", {
			arg freq = 220, amp = 0.14, wave = 0, pan = 0, phase = 0;
			var freqLag = Lag.kr(freq.max(20), 0.02);
			var ampLag = Lag.kr(amp.clip(0, 0.3), 0.04);
			var phaseTargetRad = phase.clip(0, 360) * 2pi / 360;
			var phaseVecX = Lag.kr(cos(phaseTargetRad), 0.03);
			var phaseVecY = Lag.kr(sin(phaseTargetRad), 0.03);
			var phaseRad = atan2(phaseVecY, phaseVecX);
			var phaseNorm = (phaseRad / (2pi)).wrap(0, 1);
			var sinBase = SinOsc.ar(freqLag, 0);
			var cosBase = SinOsc.ar(freqLag, pi * 0.5);
			var osc = Select.ar(
				wave.clip(0, 3),
				[
					(sinBase * phaseVecX) + (cosBase * phaseVecY),
					LFPulse.ar(freqLag, phaseNorm, 0.5).linlin(0, 1, -1, 1),
					LFTri.ar(freqLag, phaseNorm),
					LFSaw.ar(freqLag, phaseNorm)
				]
			);
			var sig = LeakDC.ar(osc) * ampLag;
			sig = Limiter.ar(sig, 0.9);
			Out.ar(0, Pan2.ar(sig, pan));
		}).add;

		Server.default.sync;

		left = Synth("DuatoneVoice", [\freq, 220, \amp, 0.14, \wave, 0, \pan, -1]);
		right = Synth("DuatoneVoice", [\freq, 220, \amp, 0.14, \wave, 1, \pan, 1]);

		this.addCommand("hz", "if", { arg msg;
			var voice = this.voiceFor(msg[1]);
			voice.set(\freq, msg[2]);
		});

		this.addCommand("wave", "ii", { arg msg;
			var voice = this.voiceFor(msg[1]);
			voice.set(\wave, msg[2]);
		});

		this.addCommand("amp", "if", { arg msg;
			var voice = this.voiceFor(msg[1]);
			voice.set(\amp, msg[2].clip(0, 0.3));
		});

		this.addCommand("pan", "if", { arg msg;
			var voice = this.voiceFor(msg[1]);
			voice.set(\pan, msg[2].clip(-1, 1));
		});

		this.addCommand("phase", "if", { arg msg;
			var voice = this.voiceFor(msg[1]);
			voice.set(\phase, msg[2].clip(0, 360));
		});
	}

	free {
		if(left.notNil) {
			left.free;
			left = nil;
		};
		if(right.notNil) {
			right.free;
			right = nil;
		};
	}
}
