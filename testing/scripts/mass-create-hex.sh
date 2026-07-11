# GO TO DIRECTORY
cd ~/fpga-effects-pedal/testing/data/wav/originals

# M4A TO WAV
for f in *.m4a; do ffmpeg -i "$f" "${f%.m4a}.wav"; done

# REMOVE M4A
rm *.m4a

# CONVERT TO HEX FILES
for f in *.wav; do      base=$(basename "${f%.wav}");     python3 ../../../scripts/wav_to_hex24.py "$f" "../../hex/${base}.hex"; done
