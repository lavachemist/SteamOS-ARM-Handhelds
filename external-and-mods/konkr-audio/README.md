# konkr-audio: Pocket FIT speaker processing

The mainline machine driver caps the Pocket FIT's WSA884x speakers at 0 dB
amplifier gain and −3 dB digital gain, because Linux has no speaker
protection for them. They are much quieter than on Android, and Steam's UI
sounds peak around −10 dBFS on top of that.

`konkr-speaker-dsp.service` runs a PipeWire filter chain
(`/usr/share/pipewire/konkr-speaker-dsp.conf`) in front of the speaker sink as
a WirePlumber smart filter. Speakers only: headphones and DisplayPort bypass
it. The chain:

1. **250 Hz high-pass** (12 dB/oct, PipeWire built-in biquads). The speakers
   don't reproduce this range; it only moves the cones and eats headroom.
2. **`konkr_limiter`** (this directory): +12 dB make-up gain into a
   stereo-linked look-ahead peak limiter at −1 dBFS, with 5 ms latency.

Peaks never exceed full scale, so the loudest possible output is the same as
without the chain and the kernel caps stay in place. Quiet audio (UI sounds,
dialogue) gets up to 12 dB louder. The volume bar (`konkr-volume`, WSA digital
volume) is applied after the chain, in the codec.

## konkr_limiter

A LADSPA plugin with no dependencies (`konkr_limiter.c`). The input is delayed
by the look-ahead D. The gain for each output sample is the average of D
sliding-window minima of the gain needed per sample, and each of those minima
already covers that output sample. So the output cannot exceed the ceiling,
and gain changes are spread over D samples instead of stepping. Release is a
one-pole rise that is never allowed above that bound.

Ports: `In L/R`, `Out L/R`, `Gain (dB)`, `Ceiling (dB)`, `Release (ms)`, and
`latency` (output, in samples, for PipeWire).

Built into the image by `scripts/build-konkr-limiter-in-rootfs.sh`, which
`apply-overlays.sh` runs. It compiles inside the rootfs so it links against
the Frame's glibc.

## Verified

- **Offline, block sizes 1–48000:**
  - 1 kHz bursts 13 dB over the ceiling, full-scale impulses, full-scale
    square wave and full-scale white noise all stay at or under −1 dBFS, even
    with the final safety clamp compiled out.
  - A quiet sine passes bit-exact apart from the gain.
- **On a Pocket FIT, at the filter output:** 1 kHz at −30 dBFS comes out at
  −18.0 dBFS (+12.0 dB), and 100 Hz comes out at −34.0 dBFS (+12 dB − 16 dB
  of high-pass).
- **By ear:** clearly louder in the Steam UI and games, with no artifacts.
