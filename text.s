.data 
.text 
.globl      MAIN  
MAIN: 	addi    s0, x0, 0          # countx = 0;    			# 4  00000413   0
	addi    s1, x0, 0          # county = 0;          			# 8  00000493	4
	addi    s2, x0, 0          # countz = 0;          			# c  00000913	8
	addi    s3, x0, 0          # innercount = 0;       			# 10 00000993	c
	addi    t0, x0, 1          # x = 1					 		# 14 00100293	10
# beginning of the loop
	addi    t3, x0, 0          # outer = 0 						# 18 00000e13	14
	addi    t4, x0, 10         # end of the outer loop constant # 1c 00a00e93	18
	addi    t6, x0, 4          # end of the inner loop constant # 20 00400f93	1c
OUTER:  beq     t3, t4, END        # using on purpose not   	# 24 03de0e63	20
	andi    t1, t3, 1          # y=outer&1 	  				    # 28 001e7313	24
	and     t2, t0, t1         # z=x&y       z=x&y				# 2c 0062f3b3	28
	beq     t0, x0, SKIPX       								# 30 00028463	2c
	addi    s0, s0, 1            # countx++;					# 34 00140413	30
SKIPX:  beq     t1, x0, SKIPY      								# 38 00030463	34
	addi    s1, s1, 1            # county++;					# 3c 00148493	38
SKIPY:  beq     t2, x0, SKIPZ      								# 40 00038463	3c
	addi    s2, s2, 1            # countz++;					# 44 00190913	40
SKIPZ:  addi    t5, x0, 0            # beginning of inner loop 	# 48 00000f13	44
INNER:  addi    t5, t5, 1            # inner++;   				# 4c 001f0f13	48
	addi    s3, s3, 1            # innercount++;  				# 50 00198993	4c
	bne     t5, t6, INNER   									# 54 ffff1ce3	50
	addi    t3, t3, 1            # outer++;  					# 58 001e0e13	54
	jal     x0, OUTER											# 5c fc9ff06f	58
END:    addi   x0, x0, 0										# 60 00000013	5c
