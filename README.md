# HFS4CPM
 Hierarchical File System for CP/M

I've got a project that I've been playing with for about two years. It started on a Z280 based SBC and I've now adapted it to the Z80 SBC from s100computers.com.

Both boards use a IDE/CF for their disk drives. I initially hard mapped logical drives A: thru H: to fixed (8M) physical partitions 0-7. This only used the first 64M of a 1G CF card.

This seemed like a bit of a waste… so I started playing around with ways to change the partition mapping on the fly.

On the Z280 board the BIOS mapped the partitions by adding a 64 track offset to each Disk Parameter Block (DPB)’s system tracks. So my initial program just fiddled with that. Worked ok with only two problems: 1) It had no way of knowing if any specific DPB was for a CF/IDE board or not. IOW: You could change the # of system tracks for a drive beyond what that drive could actually address. and 2) You were limited to an offset of 0xFFFF (65535) tracks (IOW: you could only map into the first 8 GBytes of a CF/IDE card/drive.

So my next step was to put a table of partition #’s somewhere in the BIOS so the READ/WRITE routines could just add the partition bits to the LBA. That worked better… to the limit of the (IIRC 27-bit) LBA. Something like this:

```
pppppppppppppttttttssssssss < 27-bit LBA
|||||||||||||||||||ssssssss-< 256 sectors (per track)
|||||||||||||tttttt---------< 64 tracks (per drive)
ppppppppppppp---------------< 8,192 partitions (per CF/IDE)
```

That worked better (up to 64 GBytes!) but… how can my mapping app find this table in the BIOS? 1) I could put at a fixed offset (Maybe just after the BIOS jump table?). This allowed me to change the drive mapping just by slamming new values into this table. So I wrote a small app to do just that. It would flush the logical drive, remap it and then remount it. So far so good. Pros: it was KISS; cons: it was too KISS. Since it depended on being at a specific BIOS offset after the defined jump table it wouldn't work on systems that had extra (non-standard) jump tables. entries. (and I didn't want to have to tweak a unique mapping app for each non-standard BIOS.

So… I needed a way my app to find the partition table and to know if specific logical drive supported partition mapping or not.

My next solution was to append partition information to the end of each DPB.

(Note: I initially tried appending to the DPH but ran into a problem: On a banked system the DPH’s aren’t in the TPA bank… so my app couldn’t read the DPH entries.)

First, to know if this drive supported partitions I added an “HFS|” signature. And then I appended the 16-bit partition #. All my app had to do then was locate the DPB, add an offset to the first byte after the DPB, check for the signature and then it could read & write the partition information.

Since the drive read/write routines are passed the address of the XDPH then the BIOS just needed to use that to get the address of the DPB and then add the offset (17) to the partition # stored after the DPB. This was then used to build the 27-bit LBA for the CF/IDE card.

Ok, so far so good… I added this partition support to the Z280 and Z80 SBC BIOS’s.

Now it’s time to write the mapping applications.

The first one I wrote just parses the command line looking for logical drive & partition #’s:

If it doesn’t find any it just dumps the partition #’s for all mounted logical drives that support them:

```
A> maphd
a:0 b:1 c:2 d:3
a> maphd b:4
a:0 b:4 c:2 d:3
```

Note: I specifically disabled the ability to change the partition for drive A: (the boot drive/partition) and I disallowed mapping the same partition to multiple logical drives.

Now my only problem was that I had to remember what files I put on what physical partitions.

I thought about writing a multi-partition catalog program but that was a little more work that I was willing to do.

It eventually occurred to me: why not implement a Hierarchical File System? Being used to linux I was familiar with the mkdir, cd and pwd commands.

So… now where do I store the directory information? How about in the directory entries? I just need a user # that CP/M will ignore (>=32) and isn’t otherwise in use (like the date/time stamp entries or the unused (0xE5) entry value). For reasons that should be obvious I choose 0x2E (ASCII:’.’). Just for testing I used a disk utility (zap) to change an unused (0xE5) directory entry’s user # to 0x2E and… CP/M (2.2 & 3.x) ignored it. Yay!

Ok, so now how to use it? Any sub-directory needed to know it’s parent directory (for pwd and “cd ..” to work) and then my cd app needed to know the partition # for a specified sub-directory.

```
CP/M directory entry:
offset 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F
00:    2E 47 41 4D 45 53 00 00 00 00 00 00 00 00 00 00 ‘.GAMES••••••••••’
10:    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ‘••••••••••••••••'
```

Ok, now where to put the partition #? Because of how the CP/M parser works (and I didn’t want to write my own) the file name & extensions takes up a maximum of 11 bytes:

```
CP/M directory entry:
offset 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F
00:    2E 47 45 4F 58 41 52 44 41 54 00 00 00 00 00 00 ‘.GEOWAR11DAT••••’
10:    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ‘••••••••••••••••
```

(note: because of how the CP/M parser works I choose to use the 8.3 file name/type format for directory names.)

I could put the 16-bit partition # pretty much anywhere else… but arbitrarily choose the two bytes at offset 14-15… just in case some directory scanning program I’m not aware of looked at the 16-31 byte offsets.

So now my GAMES CP/M directory entry looks like this:
```
offset 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F
00:    2E 47 41 4D 45 53 00 00 00 00 00 00 00 00 05 00 ‘.GAMES••••••••••’
10:    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ‘••••••••••••••••'
```

Note: the LSByte of the partition (at offset 0x0E) is now 5. And our ‘cd games’ command (/app) will change the mapping for this drive to partition #5.

In order to be able to ‘cd ..” our mkdir app will 1) find an unused partition (!) and write a disk label entry and a parent directory entry into the first directory entry (also optional timestamp entries). The parent directory entry’s name will be ‘.’ and it’s partition # will be the parent's partition #.

(!)How do I determine that a partition is unused?!? If its 1st entry is a disk label and it’s 2nd is a parent directory entry it’s being used. If it doesn’t have any invalid user #’s (0-31, 0x2E or 0xE5 or timestamp) it’s considered used. If all directory entries are 0xE5 it’s unused. etc.

Anyway, that’s what I’ve got working so far and I’m mostly happy with it.

Questions & feedback welcome.

## How to play with HFS4CPM

First you have to modify your BIOS to support HFS4CPM. After each DPB for drives that you want to support partitions add a four byte signature 'hfs+'.

Like this:

```
DPB0:	DPB	hstsiz,spt,numtrks,blksiz,drm,1,8000H
	db	'hfs+'  	; Partition signature
	dw	0			; Partition #
```
Set the partitions # sequentially (a:0, b:1, c:2, etc.)

Now modify the disk, track, sector to CF/IDE LBA code to support the partition # from the DPB.

```
;
;  Convert CP/M Track and Sector requests to LBA and write to drive registers
;
wrlba:	XRA	A			;CLEAR ERROR FLAG
	STA	ERFLG
;
;GET THE RELATIVE DRIVE #
;
	LXI	H,12			;add offset to address of DPB
	DAD	D			;to address of XDPH
;
	MOV	E,M			;get LSByte of DPB
	INX	H			;bump pointer
	MOV	D,M			;get MSByte of DPB
;
	LXI	H,17+4			;add offset to address of partition #
	DAD	D
;
	MOV	E,M			;get LSByte of partition #
	INX	H			;bump pointer
	MOV	A,M			;get MSByte of partition #
;
;Now we want to build our LBA as PPPPPPPP PPTTTTTT TTSSSSSS in DHL
;First we load the track (0-255) and partition # (0-1023) into AHL
;and then multiply it by 64 (six shifts left) and put the high byte into D
;and then OR the sector # (0-63) into the LSByte
;
	LHLD	@TRK			;get CPM requested Track (0-255)
	MOV	H,E			;get LSByte of partition #
;
	MVI	B,06H			;shift AHL 6 places to left (*64)
lbatrk: DAD	H			;shift HL left one bit
	RAL				;rotate overflow into Acc
	DJNZ	lbatrk			;loop around 6 times i.e x 64
;
	MOV	D,A			;get MSByte of LBA
;
	LDA	@SECT			;Get CPM requested sector
	ORA	L			;Add value in L to sector info in A
	MOV	L,A			;copy LSByte of LBA to L
;
;DHL should now contain correct LBA value
;
	MVI	E,REGcylinderMSB
	CALL	IDEwr8D			;Send info to drive

	MOV	D,H			;load lba high byte to D from H
	MVI	E,REGcylinderLSB
	CALL	IDEwr8D			;Send info to drive

	MOV	D,L			;load lba low byte to D from L
	MVI	E,REGsector
	CALL	IDEwr8D			;Send info to drive

	MVI	D,1			;For now, one sector at a time
	MVI	E,REGseccnt
	JP	IDEwr8D
```

Ok, at this point everything should "just work" (™).

maphd will let you change what partition is assigned to a logical drive.

mkdir will create a new subdirectory.

pwd will print out the working directory for a logical drive.

ddir will output a list of directories for the working directory for a logical drive.

cd will change the working directory for a logical drive.

note: since CP/M won't parse '.' or '..' (because '.' is a filename/type delimiter) you'll have to use "cd --" to go up one directory.

I also haven't added any code to allow you to mkdir or cd more than one (sub)directory at a time.

So you can't mkdir or cd to "/my/big/long/path/".

