#!/usr/bin/liquidsoap

#======================================
# Aerial Version 12.0-serene          |
# Lite Version for Lite Radios        |
# Roadmap release: February 24 2018   |
# Main Program Script                 |
# Uses code from liquidsoap.fm        |
#======================================

#======================================
# Function Definitions:               |
#======================================

# Crossfade between tracks, 
# taking the respective volume levels 
# into account in the choice of the 
# transition.
# @category Source / Track Processing
# @param ~start_next   Crossing duration, if any.
# @param ~fade_in      Fade-in duration, if any.
# @param ~fade_out     Fade-out duration, if any.
# @param ~width        Width of the volume analysis window.
# @param ~conservative Always prepare for
#                      a premature end-of-track.
# @param s             The input source.

def smart_crossfade (~start_next=5.,~fade_in=3.,
                     ~fade_out=3., ~width=2.,
             ~conservative=false,s)
  high   = -20.
  medium = -32.
  margin = 4.
  fade.out = fade.out(type="sin",duration=fade_out)
  fade.in  = fade.in(type="sin",duration=fade_in)
  add = fun (a,b) -> add(normalize=false,[b,a])
  log = log(label="smart_crossfade")

  def transition(a,b,ma,mb,sa,sb)

    list.iter(fun(x)-> 
       log(level=4,"Before: #{x}"),ma)
    list.iter(fun(x)-> 
       log(level=4,"After : #{x}"),mb)

    if
      # If A and B and not too loud and close, 
      # fully cross-fade them.
      a <= medium and 
      b <= medium and 
      abs(a - b) <= margin
    then
      log("Transition: crossed, fade-in, fade-out.")
      add(fade.out(sa),fade.in(sb))

    elsif
      # If B is significantly louder than A, 
      # only fade-out A.
      # We don't want to fade almost silent things, 
      # ask for >medium.
      b >= a + margin and a >= medium and b <= high
    then
      log("Transition: crossed, fade-out.")
      add(fade.out(sa),sb)

    elsif
      # Do not fade if it's already very low.
      b >= a + margin and a <= medium and b <= high
    then
      log("Transition: crossed, no fade-out.")
      add(sa,sb)

    elsif
      # Opposite as the previous one.
      a >= b + margin and b >= medium and a <= high
    then
      log("Transition: crossed, fade-in.")
      add(sa,fade.in(sb))


    # What to do with a loud end and 
    # a quiet beginning ?
    # A good idea is to use a jingle to separate 
    # the two tracks, but that's another story.

    else
      # Otherwise, A and B are just too loud 
      # to overlap nicely, or the difference 
      # between them is too large and 
      # overlapping would completely mask one 
      # of them.
      log("No transition: just sequencing.")
      sequence([sa, sb])
    end
  end

  smart_cross(width=width, duration=start_next, 
              conservative=conservative,
              transition,s)
end

def smooth_add(~delay=0.5,~p=0.2,~normal,~special)
  d = delay
  fade.final = fade.final(duration=d*2.)
  fade.initial = fade.initial(duration=d*2.)
  q = 1. - p
  c = amplify
  fallback(track_sensitive=false,
           [special,normal],
           transitions=[
             fun(normal,special)->
               add(normalize=false,
                   [c(p,normal),
                    c(q,fade.final(type="sin",normal)),
                    sequence([blank(duration=d),c(q,special)])]),
             fun(special,normal)->
               add(normalize=false,
                   [c(p,normal),
                    c(q,fade.initial(type="sin",normal))])
           ])
end

# A simple (short) cross-fade
def crossfade(a,b)
  add(normalize=false,
          [ sequence([ blank(duration=1.),
                       fade.initial(duration=2.,b) ]),
            fade.final(duration=2.,a) ])
end

# DJ Fading From Stream to Live and Back Again

def to_dj(jingle,old,new)
        old = fade.final(old)
        s = add ([jingle,old])
        sequence([s,new])
end

def to_radio(old,new)
        old = fade.final(old)
        new = fade.in(new)
        sequence([old,new])
end

#====================#
# Begin Main script  #
#====================#

set("log.file.path","/path/to/logfile.log")
set("log.stdout", false)
set("log.level",3 )
set("decoder.file_extensions.taglib",["mp3"])
set("decoder.mime_types.taglib",["audio/mpeg"])
set("encoder.encoder.export",["artist","title","album"])
set("tag.encodings",["UTF-8"])
set("init.daemon", true)
set("init.daemon.pidfile",false)
#set("init.daemon.pidfile.path","/path/to/pidfile.pid")

#======================================
# Set up wave line input from IceCast |
#======================================
set("harbor.bind_addr","0.0.0.0")
set("harbor.timeout",15.0)

#======================================
#Input from IceCast when DJ goes live |
#======================================
livedj=input.harbor(id="livedj",password="PASSWORD", port=9000,metadata_charset="utf8","livedj")
output.dummy(fallible=true,livedj)

#======================================
# Telnet Server Configuration         |
#======================================
set("server.telnet",false)
# Disabled as not used on lite.

#======================================
# Playlist Line Setup                 |
#======================================

playlist1=playlist(conservative=true,mode='randomize',reload=43200,reload_mode="seconds","/path/to/playlist/playlist1")
playlist2=playlist(conservative=true,mode='randomize',reload=43200,reload_mode="seconds","/path/to/playlist/playlist2")
night=playlist(conservative=true,mode='randomize',reload=43200,reload_mode="seconds","/path/to/playlist/night")
day=playlist(conservative=true,mode='randomize',reload=43200,reload_mode="seconds","/path/to/playlist/day")
failsafeplaylist=playlist(conservative=true,mode='randomize',reload=43200,reload_mode="seconds","/path/to/failsafeplaylist")

failsafe=failsafeplaylist

#==============================
# Master Schedule Setup       |
#==============================

main=rotate(weights=[1,1],[playlist1,playlist2])
night=night
day=day

s = fallback([switch(track_sensitive=true,[
                                        #  Sunday
                                        ({ (0w) and 20h-24h},main),
                                        # Night
                                        ({ (0w) and 0h-6h},night),
                                        ({ (1w) and 0h-6h},night),
                                        ({ (2w) and 0h-6h},night),
                                        ({ (3w) and 0h-6h},night),
                                        ({ (4w) and 0h-6h},night),
                                        ({ (5w) and 0h-6h},night),
                                        ({ (6w) and 0h-6h},night),
                                        # Day
                                        ({ (0w) and 6h-20h},day),
                                        ({ (1w) and 6h-24h},day),
                                        ({ (2w) and 6h-24h},day),
                                        ({ (3w) and 6h-24h},day),
                                        ({ (4w) and 6h-24h},day),
                                        ({ (5w) and 6h-24h},day),
                                        ({ (6w) and 6h-24h},day),
										({ true },fallback), #### if you accidentally forget a scheduled time this covers you
                                ]),
                        party])

s = fallback(track_sensitive=false, [s,failsafe])
s = smart_crossfade(s)
jingle = single("/path/to/transitionfile/transition.mp3")
to_dj = to_dj(jingle)
s = fallback(track_sensitive=false,
        transitions=[to_dj,to_radio],
        [strip_blank(max_blank=7.5,min_noise=0.,livedj),s])

#=========================
# Liquidsoap Flow Setup 
#=========================

s = register_flow(
  radio="RADIONAME",
  website="http://RADIOWEBSITE.COM/",
  description="RADIO DESCRIPTION",
  genre="GENRE",
  user="FLOWUSER",
  password="FLOWPASS", # TYPE/BITRATE FOR STREAMS - EG "ogg/64k"
  streams=[("TYPE/BITRATE","http://radiostream.link:port/stream.mp3"),
        ("TYPE2/BITRATE2","http://radiostream.link:port/stream.aac"),],s)

#=============
#RADIO OUTPUT
#=============

# OGG EXAMPLE
output.icecast(%vorbis(samplerate=44100, channels=2), host="HOST", port=PORT, password = "ICECASTPASSWORD", mount = "OGGMOUNT.OGG",
description="STREAM DESCRIPTION", fallible=true, url="RADIO.URL", s)

# MP3 needs id3v2=true enabled to work on any shoutcast stream, it's enabled here for legacy support.

# MP3 (128k BITRATE)
output.icecast(%mp3(stereo_mode="stereo", samplerate=44100, id3v2=true, bitrate=128), host="HOST", port=PORT,
password="ICECASTPASSWORD", mount="MP3MOUNT.MP3", description="STREAM DESCRIPTION", fallible=true, url="RADIO.URL", icy_metadata="true", s)

# AAC+ (64k) This is the most compatible stream configuration for mobile phone streams
output.icecast(%fdkaac(channels=2, samplerate=44100, bitrate=64, sbr_mode=false, afterburner=true, aot="mpeg2_he_aac_v2",
transmux="adts"), host="HOST", port=PORT, password="ICECASTPASSWORD", mount="AACMOUNT.AAC",
description="STREAM DESCRIPTION", fallible=true, url="RADIO.URL", s)

# opus (96k)
output.icecast(%opus(vbr="unconstrained", application="audio", complexity=10, max_bandwidth="full_band",samplerate=48000,
frame_size=20., bitrate=96, channels=2, signal="music"), host="localhost", port=8000, password="ICECASTPASSWORD", mount="OPUSMOUNT.OGG",
description="STREAM DESCRIPTION",fallible=true, url="RADIO.URL", s)

output.dummy(fallible=true, s)





