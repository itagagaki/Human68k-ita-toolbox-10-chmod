* chmod - change file mode
*
* Itagaki Fumihiko 28-Aug-92  Create.
*
* Usage: chmod [ -cdfvR ] {{+-=}{ashrwx}...[,]}... <file> ...

.include doscall.h
.include error.h
.include limits.h
.include stat.h
.include chrcode.h

.xref DecodeHUPAIR
.xref getlnenv
.xref strlen
.xref strcpy
.xref strfor1
.xref cat_pathname
.xref strip_excessive_slashes

MAXRECURSE	equ	64	*  サブディレクトリを削除するために再帰する回数の上限．
				*  MAXDIR （パス名のディレクトリ部 "/1/2/3/../" の長さ）
				*  が 64 であるから、31で充分であるが，
				*  シンボリック・リンクを考慮して 64 とする．
				*  スタック量にかかわる．

FLAG_c		equ	0
FLAG_d		equ	1
FLAG_f		equ	2
FLAG_v		equ	3
FLAG_R		equ	4

LNDRV_O_CREATE		equ	4*2
LNDRV_O_OPEN		equ	4*3
LNDRV_O_DELETE		equ	4*4
LNDRV_O_MKDIR		equ	4*5
LNDRV_O_RMDIR		equ	4*6
LNDRV_O_CHDIR		equ	4*7
LNDRV_O_CHMOD		equ	4*8
LNDRV_O_FILES		equ	4*9
LNDRV_O_RENAME		equ	4*10
LNDRV_O_NEWFILE		equ	4*11
LNDRV_O_FATCHK		equ	4*12
LNDRV_realpathcpy	equ	4*16
LNDRV_LINK_FILES	equ	4*17
LNDRV_OLD_LINK_FILES	equ	4*18
LNDRV_link_nest_max	equ	4*19
LNDRV_getrealpath	equ	4*20

.text
start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	stack_bottom,a7			*  A7 := スタックの底
		DOS	_GETPDB
		movea.l	d0,a0				*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  lndrv が組み込まれているかどうかを検査する
	*
		bsr	getlnenv
		move.l	d0,lndrv
	*
	*  オプション引数を解釈する
	*
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		moveq	#0,d5				*  D5.L : flags
decode_opt_loop1:
		movea.l	a0,a1
		tst.l	d7
		beq	too_few_args

		cmpi.b	#'-',(a0)+
		bne	decode_opt_done

		subq.l	#1,d7
		move.b	(a0)+,d0
decode_opt_loop2:
		moveq	#FLAG_c,d1
		cmp.b	#'c',d0
		beq	set_option

		moveq	#FLAG_d,d1
		cmp.b	#'d',d0
		beq	set_option

		moveq	#FLAG_f,d1
		cmp.b	#'f',d0
		beq	set_option

		moveq	#FLAG_v,d1
		cmp.b	#'v',d0
		beq	set_option

		moveq	#FLAG_R,d1
		cmp.b	#'R',d0
		bne	decode_opt_break
set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_opt_break:
		addq.l	#1,d7
decode_opt_done:
		movea.l	a1,a0
		subq.l	#1,d7
		bls	too_few_args
	*
	*  モード引数を解釈する
	*
		move.b	#$ff,mode_mask
		clr.b	mode_plus
decode_mode_loop1:
		move.b	(a0)+,d0
		beq	decode_mode_done

		cmp.b	#',',d0
		beq	decode_mode_loop1

		subq.l	#1,a0
decode_mode_loop2:
		move.b	(a0)+,d0
		cmp.b	#'u',d0
		beq	decode_mode_loop2

		cmp.b	#'g',d0
		beq	decode_mode_loop2

		cmp.b	#'o',d0
		beq	decode_mode_loop2

		cmp.b	#'a',d0
		beq	decode_mode_loop2
decode_mode_loop3:
		cmp.b	#'+',d0
		beq	decode_mode_plus

		cmp.b	#'-',d0
		beq	decode_mode_minus

		cmp.b	#'=',d0
		beq	decode_mode_equal
bad_arg:
		movea.l	a1,a0
		lea	msg_bad_arg(pc),a2
		bsr	werror_myname_word_colon_msg
		bra	usage

decode_mode_equal:
		move.b	#(MODEBIT_VOL|MODEBIT_DIR|MODEBIT_LNK),mode_mask
		clr.b	mode_plus
decode_mode_plus:
		bsr	decode_mode_sub
		or.b	d1,mode_plus
		bra	decode_mode_continue

decode_mode_minus:
		bsr	decode_mode_sub
		not.b	d1
		and.b	d1,mode_mask
		and.b	d1,mode_plus
decode_mode_continue:
		tst.b	d0
		beq	decode_mode_done

		cmp.b	#',',d0
		beq	decode_mode_loop1
		bra	decode_mode_loop3

decode_mode_sub:
		moveq	#0,d1
decode_mode_sub_loop:
		move.b	(a0)+,d0
		moveq	#MODEBIT_ARC,d2
		cmp.b	#'a',d0
		beq	decode_mode_sub_set

		moveq	#MODEBIT_SYS,d2
		cmp.b	#'s',d0
		beq	decode_mode_sub_set

		moveq	#MODEBIT_HID,d2
		cmp.b	#'h',d0
		beq	decode_mode_sub_set

		cmp.b	#'r',d0
		beq	decode_mode_sub_loop

		moveq	#MODEBIT_RDO,d2
		cmp.b	#'w',d0
		beq	decode_mode_sub_set

		moveq	#MODEBIT_EXE,d2
		cmp.b	#'x',d0
		beq	decode_mode_sub_set
decode_mode_sub_done:
		rts

decode_mode_sub_set:
		bset	d2,d1
		bra	decode_mode_sub_loop

decode_mode_done:
		moveq	#0,d6				*  D6.W : エラー・コード
chmod_loop:
		movea.l	a0,a1
		bsr	strfor1
		move.l	a0,-(a7)
		movea.l	a1,a0
		bsr	strip_excessive_slashes
		bsr	chmod_one
		movea.l	(a7)+,a0
		subq.l	#1,d7
		bne	chmod_loop
exit_program:
		move.w	d6,-(a7)
		DOS	_EXIT2

too_few_args:
		lea	msg_too_few_args(pc),a0
		bsr	werror_myname_and_msg
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

insufficient_memory:
		lea	msg_no_memory(pc),a0
chmod_error_exit_3:
		bsr	werror_myname_and_msg
		moveq	#3,d6
		bra	exit_program
*****************************************************************
* chmod_one
*
* CALL
*      A0     filename
*
* RETURN
*      D0-D2/A0-A3   破壊
*****************************************************************
chmod_one:
		moveq	#0,d3
chmod_recurse:
	*
	*  A0 がシンボリック・リンクなら，その参照パス名を，そうでなければ A0 を，
	*  A1 にセットし，その属性を D0.L に得る．
	*
		movea.l	a0,a1
		bsr	lgetmode
		bmi	chmod_nomode

		btst	#MODEBIT_LNK,d0
		beq	do_chmod_one

		btst	#FLAG_d,d5
		bne	chmod_one_return

		lea	msg_cannot_access_link(pc),a2
		move.l	lndrv,d0
		beq	werror_myname_word_colon_msg_f

		movea.l	d0,a2
		movea.l	LNDRV_getrealpath(a2),a2
		lea	refname(pc),a1
		clr.l	-(a7)
		DOS	_SUPER				*  スーパーバイザ・モードに切り換える
		addq.l	#4,a7
		move.l	d0,-(a7)			*  前の SSP の値
		movem.l	d2-d7/a0-a1/a4-a6,-(a7)
		move.l	a0,-(a7)
		move.l	a1,-(a7)
		jsr	(a2)
		addq.l	#8,a7
		movem.l	(a7)+,d2-d7/a0-a1/a4-a6
		move.l	d0,d1
		DOS	_SUPER				*  ユーザ・モードに戻す
		addq.l	#4,a7
		lea	msg_bad_link(pc),a2
		tst.l	d1
		bmi	werror_myname_word_colon_msg_f

		exg	a0,a1
		bsr	lgetmode
		exg	a0,a1
		bpl	do_chmod_one
chmod_nomode:
	*
	*  A1 の属性は取得できない -> A1 のままでは chmod できない -> nameck を試す．
	*
		move.l	d0,d1
		lea	nameckbuf(pc),a2
		move.l	a2,-(a7)
		move.l	a1,-(a7)
		DOS	_NAMECK
		addq.l	#8,a7
		tst.l	d0
		bmi	perror

		move.l	d1,d0
		tst.b	67(a2)				*  basename が
		bne	perror				*  あるのに属性を取得できない ... エラー

		tst.b	3(a2)				*  ルート・ディレクトリでは
		bne	chmod_nomode_1			*  ない ... このディレクトリ名で chmod する
		*
		*  指定されたのはルート・ディレクトリであった
		*
		lea	msg_cannot_chmod_root(pc),a2
		bsr	werror_myname_word_colon_msg_f
		bra	chmod_directory_contents

chmod_nomode_1:
		movea.l	a2,a1
		exg	a0,a1
		bsr	strip_excessive_slashes
		bsr	lgetmode
		exg	a0,a1
		bmi	perror
do_chmod_one:
	*
	*  A1 を chmod する
	*
		move.b	d0,d2
		bchg	#MODEBIT_RDO,d0
		and.b	mode_mask,d0
		or.b	mode_plus,d0
		bchg	#MODEBIT_RDO,d0
		move.w	d0,d1				*  D1.W : 変更後のモード
		lea	msg_retained(pc),a2
		eor.b	d1,d2
		and.b	#(MODEVAL_ARC|MODEVAL_SYS|MODEVAL_HID|MODEVAL_RDO|MODEVAL_EXE),d2
		beq	chmod_one_describe_0

		move.w	d1,d0
		exg	a0,a1
		bsr	lchmod
		exg	a0,a1
		bpl	chmod_one_describe_1

		bsr	perror
		bra	chmod_one_done

chmod_one_describe_1:
		lea	msg_changed(pc),a2
		btst	#FLAG_c,d5
		bne	chmod_one_describe_2
chmod_one_describe_0:
		btst	#FLAG_v,d5
		beq	chmod_one_done
chmod_one_describe_2:
		move.l	a0,-(a7)
		DOS	_PRINT
		pea	msg_no_mode_ha(pc)
		DOS	_PRINT
		moveq	#'v',d0
		btst	#MODEBIT_VOL,d1
		bne	chmod_one_describe_l

		moveq	#'d',d0
		btst	#MODEBIT_DIR,d1
		bne	chmod_one_describe_l

		moveq	#'-',d0
chmod_one_describe_l:
		move.w	d0,(a7)
		DOS	_PUTCHAR
		moveq	#'a',d0
		btst	#MODEBIT_ARC,d1
		bne	chmod_one_describe_a

		moveq	#'-',d0
chmod_one_describe_a:
		move.w	d0,(a7)
		DOS	_PUTCHAR
		move.w	d0,(a7)
		DOS	_PUTCHAR
		moveq	#'s',d0
		btst	#MODEBIT_SYS,d1
		bne	chmod_one_describe_s

		moveq	#'-',d0
chmod_one_describe_s:
		move.w	d0,(a7)
		DOS	_PUTCHAR
		moveq	#'h',d0
		btst	#MODEBIT_HID,d1
		bne	chmod_one_describe_h

		moveq	#'-',d0
chmod_one_describe_h:
		move.w	d0,(a7)
		DOS	_PUTCHAR
		move.w	#'r',(a7)
		DOS	_PUTCHAR
		moveq	#'w',d0
		btst	#MODEBIT_RDO,d1
		beq	chmod_one_describe_w

		moveq	#'-',d0
chmod_one_describe_w:
		move.w	d0,(a7)
		DOS	_PUTCHAR
		moveq	#'x',d0
		btst	#MODEBIT_EXE,d1
		bne	chmod_one_describe_x

		moveq	#'-',d0
chmod_one_describe_x:
		move.w	d0,(a7)
		DOS	_PUTCHAR
		move.l	a2,(a7)
		DOS	_PRINT
		addq.l	#8,a7
chmod_one_done:
		btst	#MODEBIT_DIR,d1
		beq	chmod_one_return
chmod_directory_contents:
		btst	#FLAG_R,d5
		beq	chmod_one_return

		lea	msg_dir_too_deep(pc),a2
		addq.l	#1,d3				*  ディレクトリの深さをインクリメント
		cmp.l	#MAXRECURSE,d3
		bhi	werror_myname_word_colon_msg

chmod_pathbuf = -((((MAXPATH+MAXTAIL+1)+1)>>1)<<1)
chmod_filesbuf = chmod_pathbuf-(((STATBUFSIZE+1)>>1)<<1)
chmod_autosize = -chmod_filesbuf
chmod_recurse_stacksize	equ	chmod_autosize+4*4	* 4*4 ... A2/A3/A6/PC

		link	a6,#chmod_filesbuf
		movea.l	a0,a1
		lea	dos_wildcard_all(pc),a2
		lea	chmod_pathbuf(a6),a0
		bsr	cat_pathname
		bmi	chmod_one_too_long_pathname

		movea.l	a0,a2
		*
		*  A2 : chmod_pathbuf : (A0)/*.*
		*                            |
		*                            A3
		move.w	#MODEVAL_ALL,-(a7)		*  すべてのエントリを検索する
		move.l	a2,-(a7)
		pea	chmod_filesbuf(a6)
		DOS	_FILES
		lea	10(a7),a7
chmod_dir_loop:
		tst.l	d0
		bmi	chmod_dir_return

		lea	chmod_filesbuf+ST_NAME(a6),a1
		cmpi.b	#'.',(a1)
		bne	chmod_dir_1

		tst.b	1(a1)
		beq	chmod_dir_continue

		cmpi.b	#'.',1(a1)
		bne	chmod_dir_1

		tst.b	2(a1)
		beq	chmod_dir_continue
chmod_dir_1:
		movea.l	a3,a0
		bsr	strcpy
		movea.l	a2,a0
		movem.l	a2-a3,-(a7)
		bsr	chmod_one
		movem.l	(a7)+,a2-a3
chmod_dir_continue:
		pea	chmod_filesbuf(a6)
		DOS	_NFILES
		addq.l	#4,a7
		bra	chmod_dir_loop

chmod_one_too_long_pathname:
		lea	msg_too_long_pathname(pc),a2
		bsr	werror_myname_word_colon_msg_f
chmod_dir_return:
		unlk	a6
		subq.l	#1,d3
chmod_one_return:
		rts
*****************************************************************
lgetmode:
		moveq	#-1,d0
lchmod:
		move.w	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_CHMOD
		addq.l	#6,a7
		tst.l	d0
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
werror_myname_and_msg:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
werror_myname_word_colon_msg_f:
		btst	#FLAG_f,d5
		bne	werror_myname_word_colon_msg_return
werror_myname_word_colon_msg:
		bsr	werror_myname_and_msg
		move.l	a0,-(a7)
		lea	msg_colon(pc),a0
werror_word_msg_and_set_error:
		bsr	werror
		movea.l	a2,a0
		bsr	werror
		lea	msg_newline(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
werror_myname_word_colon_msg_return:
		moveq	#2,d6
		rts
*****************************************************************
perror:
		movem.l	d0/a2,-(a7)
		not.l	d0		* -1 -> 0, -2 -> 1, ...
		cmp.l	#25,d0
		bls	perror_1

		moveq	#0,d0
perror_1:
		lea	perror_table(pc),a2
		lsl.l	#1,d0
		move.w	(a2,d0.l),d0
		lea	sys_errmsgs(pc),a2
		lea	(a2,d0.w),a2
		bsr	werror_myname_word_colon_msg_f
		movem.l	(a7)+,d0/a2
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## chmod 1.0 ##  Copyright(C)1992 by Itagaki Fumihiko',0

.even
perror_table:
	dc.w	msg_error-sys_errmsgs			*   0 ( -1)
	dc.w	msg_nofile-sys_errmsgs			*   1 ( -2)
	dc.w	msg_nofile-sys_errmsgs			*   2 ( -3)
	dc.w	msg_error-sys_errmsgs			*   3 ( -4)
	dc.w	msg_error-sys_errmsgs			*   4 ( -5)
	dc.w	msg_error-sys_errmsgs			*   5 ( -6)
	dc.w	msg_error-sys_errmsgs			*   6 ( -7)
	dc.w	msg_error-sys_errmsgs			*   7 ( -8)
	dc.w	msg_error-sys_errmsgs			*   8 ( -9)
	dc.w	msg_error-sys_errmsgs			*   9 (-10)
	dc.w	msg_error-sys_errmsgs			*  10 (-11)
	dc.w	msg_error-sys_errmsgs			*  11 (-12)
	dc.w	msg_bad_name-sys_errmsgs		*  12 (-13)
	dc.w	msg_error-sys_errmsgs			*  13 (-14)
	dc.w	msg_bad_drive-sys_errmsgs		*  14 (-15)
	dc.w	msg_error-sys_errmsgs			*  15 (-16)
	dc.w	msg_error-sys_errmsgs			*  16 (-17)
	dc.w	msg_error-sys_errmsgs			*  17 (-18)
	dc.w	msg_error-sys_errmsgs			*  18 (-19)
	dc.w	msg_error-sys_errmsgs			*  19 (-20)
	dc.w	msg_error-sys_errmsgs			*  20 (-21)
	dc.w	msg_error-sys_errmsgs			*  21 (-22)
	dc.w	msg_error-sys_errmsgs			*  22 (-23)
	dc.w	msg_error-sys_errmsgs			*  23 (-24)
	dc.w	msg_error-sys_errmsgs			*  24 (-25)
	dc.w	msg_error-sys_errmsgs			*  25 (-26)

sys_errmsgs:
msg_error:		dc.b	'エラー',0
msg_nofile:		dc.b	'このようなファイルやディレクトリはありません',0
msg_bad_name:		dc.b	'名前が無効です',0
msg_bad_drive:		dc.b	'ドライブの指定が無効です',0

msg_myname:			dc.b	'chmod'
msg_colon:			dc.b	': ',0
msg_no_memory:			dc.b	'メモリが足りません',CR,LF,0
msg_bad_arg:			dc.b	'引数が正しくありません',0
msg_too_few_args:		dc.b	'引数が足りません',0
msg_too_long_pathname:		dc.b	'パス名が長過ぎます',0
msg_cannot_chmod_root:		dc.b	'ルート・ディレクトリの属性は変更できません',0
msg_cannot_access_link:		dc.b	'lndrvが組み込まれていないためシンボリック・リンク参照ファイルにアクセスできません',0
msg_bad_link:			dc.b	'異常なシンボリック・リンクです',0
msg_dir_too_deep:		dc.b	'ディレクトリが深過ぎて処理できません',0
msg_no_mode_ha:			dc.b	' の属性は ',0
msg_retained:			dc.b	' のままに維持されました',CR,LF,0
msg_changed:			dc.b	' に変更されました',CR,LF,0
msg_usage:			dc.b	CR,LF
				dc.b	'使用法:  chmod [-cdfvR] {[ugoa]{{+-=}[ashrwx]}...}[,...] <ファイル> ...'
msg_newline:			dc.b	CR,LF,0
dos_wildcard_all:		dc.b	'*.*',0
*****************************************************************
.bss

.even
lndrv:			ds.l	1
refname:		ds.b	128
nameckbuf:		ds.b	91
mode_mask:		ds.b	1
mode_plus:		ds.b	1
.even
			ds.b	4096+chmod_recurse_stacksize*(MAXRECURSE+1)
			*  必要なスタック量は，再帰の度に消費されるスタック量と
			*  その回数とで決まる．
			*  その他にマージンを含めたミニマム量として 4096バイトを確保しておく．
			*  このプログラムでは 4096バイトあれば充分である．
			*  （lndrv が 1.5KB程喰う可能性がある）
.even
stack_bottom:
*****************************************************************

.end start
