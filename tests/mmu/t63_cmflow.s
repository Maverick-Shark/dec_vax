; t63_cmflow - PDP-11 compatibility mode program control and tracing
; against the reference simulator; written by tests/mmu/gen/mk_t63.py
; (which see).
;@ dump=18000:C00
;@ dump=6E00:100
;@ clocks=2000000
LOG	= ^x18000
KSP	= 0
USP	= 3
SCBB	= ^x11
CMPSL	= ^x83C00000

	.org	^x1000
start:	movl	#^x17800, sp		; above 64K: the compat code is
					; up to FFFF
	clrl	r0
	movab	unexp+1, r1
scbfill: movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movab	cmexc, @#^x30
	movab	trace, @#^x28
	mtpr	#0, #SCBB
	mtpr	#^x17000, #KSP
	mtpr	#^x16800, #USP
	movl	#LOG, r11
	clrl	r9
	pushl	#CMPSL
	pushl	#^x8000
	rei


	.org	^x8000
	.pdp11
	mov	#^x7000, sp
; ---- branches: not taken, the BPT after it; taken, the BPT at the target
	ccc
	br	t1
	bpt
	br	n2
t1:	bpt
n2:
	ccc
	.word	^o261
	br	t3
	bpt
	br	n4
t3:	bpt
n4:
	ccc
	.word	^o262
	br	t5
	bpt
	br	n6
t5:	bpt
n6:
	ccc
	.word	^o263
	br	t7
	bpt
	br	n8
t7:	bpt
n8:
	ccc
	.word	^o264
	br	t9
	bpt
	br	n10
t9:	bpt
n10:
	ccc
	.word	^o265
	br	t11
	bpt
	br	n12
t11:	bpt
n12:
	ccc
	.word	^o266
	br	t13
	bpt
	br	n14
t13:	bpt
n14:
	ccc
	.word	^o267
	br	t15
	bpt
	br	n16
t15:	bpt
n16:
	ccc
	.word	^o270
	br	t17
	bpt
	br	n18
t17:	bpt
n18:
	ccc
	.word	^o271
	br	t19
	bpt
	br	n20
t19:	bpt
n20:
	ccc
	.word	^o272
	br	t21
	bpt
	br	n22
t21:	bpt
n22:
	ccc
	.word	^o273
	br	t23
	bpt
	br	n24
t23:	bpt
n24:
	ccc
	.word	^o274
	br	t25
	bpt
	br	n26
t25:	bpt
n26:
	ccc
	.word	^o275
	br	t27
	bpt
	br	n28
t27:	bpt
n28:
	ccc
	.word	^o276
	br	t29
	bpt
	br	n30
t29:	bpt
n30:
	ccc
	.word	^o277
	br	t31
	bpt
	br	n32
t31:	bpt
n32:
	ccc
	bne	t33
	bpt
	br	n34
t33:	bpt
n34:
	ccc
	.word	^o261
	bne	t35
	bpt
	br	n36
t35:	bpt
n36:
	ccc
	.word	^o262
	bne	t37
	bpt
	br	n38
t37:	bpt
n38:
	ccc
	.word	^o263
	bne	t39
	bpt
	br	n40
t39:	bpt
n40:
	ccc
	.word	^o264
	bne	t41
	bpt
	br	n42
t41:	bpt
n42:
	ccc
	.word	^o265
	bne	t43
	bpt
	br	n44
t43:	bpt
n44:
	ccc
	.word	^o266
	bne	t45
	bpt
	br	n46
t45:	bpt
n46:
	ccc
	.word	^o267
	bne	t47
	bpt
	br	n48
t47:	bpt
n48:
	ccc
	.word	^o270
	bne	t49
	bpt
	br	n50
t49:	bpt
n50:
	ccc
	.word	^o271
	bne	t51
	bpt
	br	n52
t51:	bpt
n52:
	ccc
	.word	^o272
	bne	t53
	bpt
	br	n54
t53:	bpt
n54:
	ccc
	.word	^o273
	bne	t55
	bpt
	br	n56
t55:	bpt
n56:
	ccc
	.word	^o274
	bne	t57
	bpt
	br	n58
t57:	bpt
n58:
	ccc
	.word	^o275
	bne	t59
	bpt
	br	n60
t59:	bpt
n60:
	ccc
	.word	^o276
	bne	t61
	bpt
	br	n62
t61:	bpt
n62:
	ccc
	.word	^o277
	bne	t63
	bpt
	br	n64
t63:	bpt
n64:
	ccc
	beq	t65
	bpt
	br	n66
t65:	bpt
n66:
	ccc
	.word	^o261
	beq	t67
	bpt
	br	n68
t67:	bpt
n68:
	ccc
	.word	^o262
	beq	t69
	bpt
	br	n70
t69:	bpt
n70:
	ccc
	.word	^o263
	beq	t71
	bpt
	br	n72
t71:	bpt
n72:
	ccc
	.word	^o264
	beq	t73
	bpt
	br	n74
t73:	bpt
n74:
	ccc
	.word	^o265
	beq	t75
	bpt
	br	n76
t75:	bpt
n76:
	ccc
	.word	^o266
	beq	t77
	bpt
	br	n78
t77:	bpt
n78:
	ccc
	.word	^o267
	beq	t79
	bpt
	br	n80
t79:	bpt
n80:
	ccc
	.word	^o270
	beq	t81
	bpt
	br	n82
t81:	bpt
n82:
	ccc
	.word	^o271
	beq	t83
	bpt
	br	n84
t83:	bpt
n84:
	ccc
	.word	^o272
	beq	t85
	bpt
	br	n86
t85:	bpt
n86:
	ccc
	.word	^o273
	beq	t87
	bpt
	br	n88
t87:	bpt
n88:
	ccc
	.word	^o274
	beq	t89
	bpt
	br	n90
t89:	bpt
n90:
	ccc
	.word	^o275
	beq	t91
	bpt
	br	n92
t91:	bpt
n92:
	ccc
	.word	^o276
	beq	t93
	bpt
	br	n94
t93:	bpt
n94:
	ccc
	.word	^o277
	beq	t95
	bpt
	br	n96
t95:	bpt
n96:
	ccc
	bge	t97
	bpt
	br	n98
t97:	bpt
n98:
	ccc
	.word	^o261
	bge	t99
	bpt
	br	n100
t99:	bpt
n100:
	ccc
	.word	^o262
	bge	t101
	bpt
	br	n102
t101:	bpt
n102:
	ccc
	.word	^o263
	bge	t103
	bpt
	br	n104
t103:	bpt
n104:
	ccc
	.word	^o264
	bge	t105
	bpt
	br	n106
t105:	bpt
n106:
	ccc
	.word	^o265
	bge	t107
	bpt
	br	n108
t107:	bpt
n108:
	ccc
	.word	^o266
	bge	t109
	bpt
	br	n110
t109:	bpt
n110:
	ccc
	.word	^o267
	bge	t111
	bpt
	br	n112
t111:	bpt
n112:
	ccc
	.word	^o270
	bge	t113
	bpt
	br	n114
t113:	bpt
n114:
	ccc
	.word	^o271
	bge	t115
	bpt
	br	n116
t115:	bpt
n116:
	ccc
	.word	^o272
	bge	t117
	bpt
	br	n118
t117:	bpt
n118:
	ccc
	.word	^o273
	bge	t119
	bpt
	br	n120
t119:	bpt
n120:
	ccc
	.word	^o274
	bge	t121
	bpt
	br	n122
t121:	bpt
n122:
	ccc
	.word	^o275
	bge	t123
	bpt
	br	n124
t123:	bpt
n124:
	ccc
	.word	^o276
	bge	t125
	bpt
	br	n126
t125:	bpt
n126:
	ccc
	.word	^o277
	bge	t127
	bpt
	br	n128
t127:	bpt
n128:
	ccc
	blt	t129
	bpt
	br	n130
t129:	bpt
n130:
	ccc
	.word	^o261
	blt	t131
	bpt
	br	n132
t131:	bpt
n132:
	ccc
	.word	^o262
	blt	t133
	bpt
	br	n134
t133:	bpt
n134:
	ccc
	.word	^o263
	blt	t135
	bpt
	br	n136
t135:	bpt
n136:
	ccc
	.word	^o264
	blt	t137
	bpt
	br	n138
t137:	bpt
n138:
	ccc
	.word	^o265
	blt	t139
	bpt
	br	n140
t139:	bpt
n140:
	ccc
	.word	^o266
	blt	t141
	bpt
	br	n142
t141:	bpt
n142:
	ccc
	.word	^o267
	blt	t143
	bpt
	br	n144
t143:	bpt
n144:
	ccc
	.word	^o270
	blt	t145
	bpt
	br	n146
t145:	bpt
n146:
	ccc
	.word	^o271
	blt	t147
	bpt
	br	n148
t147:	bpt
n148:
	ccc
	.word	^o272
	blt	t149
	bpt
	br	n150
t149:	bpt
n150:
	ccc
	.word	^o273
	blt	t151
	bpt
	br	n152
t151:	bpt
n152:
	ccc
	.word	^o274
	blt	t153
	bpt
	br	n154
t153:	bpt
n154:
	ccc
	.word	^o275
	blt	t155
	bpt
	br	n156
t155:	bpt
n156:
	ccc
	.word	^o276
	blt	t157
	bpt
	br	n158
t157:	bpt
n158:
	ccc
	.word	^o277
	blt	t159
	bpt
	br	n160
t159:	bpt
n160:
	ccc
	bgt	t161
	bpt
	br	n162
t161:	bpt
n162:
	ccc
	.word	^o261
	bgt	t163
	bpt
	br	n164
t163:	bpt
n164:
	ccc
	.word	^o262
	bgt	t165
	bpt
	br	n166
t165:	bpt
n166:
	ccc
	.word	^o263
	bgt	t167
	bpt
	br	n168
t167:	bpt
n168:
	ccc
	.word	^o264
	bgt	t169
	bpt
	br	n170
t169:	bpt
n170:
	ccc
	.word	^o265
	bgt	t171
	bpt
	br	n172
t171:	bpt
n172:
	ccc
	.word	^o266
	bgt	t173
	bpt
	br	n174
t173:	bpt
n174:
	ccc
	.word	^o267
	bgt	t175
	bpt
	br	n176
t175:	bpt
n176:
	ccc
	.word	^o270
	bgt	t177
	bpt
	br	n178
t177:	bpt
n178:
	ccc
	.word	^o271
	bgt	t179
	bpt
	br	n180
t179:	bpt
n180:
	ccc
	.word	^o272
	bgt	t181
	bpt
	br	n182
t181:	bpt
n182:
	ccc
	.word	^o273
	bgt	t183
	bpt
	br	n184
t183:	bpt
n184:
	ccc
	.word	^o274
	bgt	t185
	bpt
	br	n186
t185:	bpt
n186:
	ccc
	.word	^o275
	bgt	t187
	bpt
	br	n188
t187:	bpt
n188:
	ccc
	.word	^o276
	bgt	t189
	bpt
	br	n190
t189:	bpt
n190:
	ccc
	.word	^o277
	bgt	t191
	bpt
	br	n192
t191:	bpt
n192:
	ccc
	ble	t193
	bpt
	br	n194
t193:	bpt
n194:
	ccc
	.word	^o261
	ble	t195
	bpt
	br	n196
t195:	bpt
n196:
	ccc
	.word	^o262
	ble	t197
	bpt
	br	n198
t197:	bpt
n198:
	ccc
	.word	^o263
	ble	t199
	bpt
	br	n200
t199:	bpt
n200:
	ccc
	.word	^o264
	ble	t201
	bpt
	br	n202
t201:	bpt
n202:
	ccc
	.word	^o265
	ble	t203
	bpt
	br	n204
t203:	bpt
n204:
	ccc
	.word	^o266
	ble	t205
	bpt
	br	n206
t205:	bpt
n206:
	ccc
	.word	^o267
	ble	t207
	bpt
	br	n208
t207:	bpt
n208:
	ccc
	.word	^o270
	ble	t209
	bpt
	br	n210
t209:	bpt
n210:
	ccc
	.word	^o271
	ble	t211
	bpt
	br	n212
t211:	bpt
n212:
	ccc
	.word	^o272
	ble	t213
	bpt
	br	n214
t213:	bpt
n214:
	ccc
	.word	^o273
	ble	t215
	bpt
	br	n216
t215:	bpt
n216:
	ccc
	.word	^o274
	ble	t217
	bpt
	br	n218
t217:	bpt
n218:
	ccc
	.word	^o275
	ble	t219
	bpt
	br	n220
t219:	bpt
n220:
	ccc
	.word	^o276
	ble	t221
	bpt
	br	n222
t221:	bpt
n222:
	ccc
	.word	^o277
	ble	t223
	bpt
	br	n224
t223:	bpt
n224:
	ccc
	bpl	t225
	bpt
	br	n226
t225:	bpt
n226:
	ccc
	.word	^o261
	bpl	t227
	bpt
	br	n228
t227:	bpt
n228:
	ccc
	.word	^o262
	bpl	t229
	bpt
	br	n230
t229:	bpt
n230:
	ccc
	.word	^o263
	bpl	t231
	bpt
	br	n232
t231:	bpt
n232:
	ccc
	.word	^o264
	bpl	t233
	bpt
	br	n234
t233:	bpt
n234:
	ccc
	.word	^o265
	bpl	t235
	bpt
	br	n236
t235:	bpt
n236:
	ccc
	.word	^o266
	bpl	t237
	bpt
	br	n238
t237:	bpt
n238:
	ccc
	.word	^o267
	bpl	t239
	bpt
	br	n240
t239:	bpt
n240:
	ccc
	.word	^o270
	bpl	t241
	bpt
	br	n242
t241:	bpt
n242:
	ccc
	.word	^o271
	bpl	t243
	bpt
	br	n244
t243:	bpt
n244:
	ccc
	.word	^o272
	bpl	t245
	bpt
	br	n246
t245:	bpt
n246:
	ccc
	.word	^o273
	bpl	t247
	bpt
	br	n248
t247:	bpt
n248:
	ccc
	.word	^o274
	bpl	t249
	bpt
	br	n250
t249:	bpt
n250:
	ccc
	.word	^o275
	bpl	t251
	bpt
	br	n252
t251:	bpt
n252:
	ccc
	.word	^o276
	bpl	t253
	bpt
	br	n254
t253:	bpt
n254:
	ccc
	.word	^o277
	bpl	t255
	bpt
	br	n256
t255:	bpt
n256:
	ccc
	bmi	t257
	bpt
	br	n258
t257:	bpt
n258:
	ccc
	.word	^o261
	bmi	t259
	bpt
	br	n260
t259:	bpt
n260:
	ccc
	.word	^o262
	bmi	t261
	bpt
	br	n262
t261:	bpt
n262:
	ccc
	.word	^o263
	bmi	t263
	bpt
	br	n264
t263:	bpt
n264:
	ccc
	.word	^o264
	bmi	t265
	bpt
	br	n266
t265:	bpt
n266:
	ccc
	.word	^o265
	bmi	t267
	bpt
	br	n268
t267:	bpt
n268:
	ccc
	.word	^o266
	bmi	t269
	bpt
	br	n270
t269:	bpt
n270:
	ccc
	.word	^o267
	bmi	t271
	bpt
	br	n272
t271:	bpt
n272:
	ccc
	.word	^o270
	bmi	t273
	bpt
	br	n274
t273:	bpt
n274:
	ccc
	.word	^o271
	bmi	t275
	bpt
	br	n276
t275:	bpt
n276:
	ccc
	.word	^o272
	bmi	t277
	bpt
	br	n278
t277:	bpt
n278:
	ccc
	.word	^o273
	bmi	t279
	bpt
	br	n280
t279:	bpt
n280:
	ccc
	.word	^o274
	bmi	t281
	bpt
	br	n282
t281:	bpt
n282:
	ccc
	.word	^o275
	bmi	t283
	bpt
	br	n284
t283:	bpt
n284:
	ccc
	.word	^o276
	bmi	t285
	bpt
	br	n286
t285:	bpt
n286:
	ccc
	.word	^o277
	bmi	t287
	bpt
	br	n288
t287:	bpt
n288:
	ccc
	bhi	t289
	bpt
	br	n290
t289:	bpt
n290:
	ccc
	.word	^o261
	bhi	t291
	bpt
	br	n292
t291:	bpt
n292:
	ccc
	.word	^o262
	bhi	t293
	bpt
	br	n294
t293:	bpt
n294:
	ccc
	.word	^o263
	bhi	t295
	bpt
	br	n296
t295:	bpt
n296:
	ccc
	.word	^o264
	bhi	t297
	bpt
	br	n298
t297:	bpt
n298:
	ccc
	.word	^o265
	bhi	t299
	bpt
	br	n300
t299:	bpt
n300:
	ccc
	.word	^o266
	bhi	t301
	bpt
	br	n302
t301:	bpt
n302:
	ccc
	.word	^o267
	bhi	t303
	bpt
	br	n304
t303:	bpt
n304:
	ccc
	.word	^o270
	bhi	t305
	bpt
	br	n306
t305:	bpt
n306:
	ccc
	.word	^o271
	bhi	t307
	bpt
	br	n308
t307:	bpt
n308:
	ccc
	.word	^o272
	bhi	t309
	bpt
	br	n310
t309:	bpt
n310:
	ccc
	.word	^o273
	bhi	t311
	bpt
	br	n312
t311:	bpt
n312:
	ccc
	.word	^o274
	bhi	t313
	bpt
	br	n314
t313:	bpt
n314:
	ccc
	.word	^o275
	bhi	t315
	bpt
	br	n316
t315:	bpt
n316:
	ccc
	.word	^o276
	bhi	t317
	bpt
	br	n318
t317:	bpt
n318:
	ccc
	.word	^o277
	bhi	t319
	bpt
	br	n320
t319:	bpt
n320:
	ccc
	blos	t321
	bpt
	br	n322
t321:	bpt
n322:
	ccc
	.word	^o261
	blos	t323
	bpt
	br	n324
t323:	bpt
n324:
	ccc
	.word	^o262
	blos	t325
	bpt
	br	n326
t325:	bpt
n326:
	ccc
	.word	^o263
	blos	t327
	bpt
	br	n328
t327:	bpt
n328:
	ccc
	.word	^o264
	blos	t329
	bpt
	br	n330
t329:	bpt
n330:
	ccc
	.word	^o265
	blos	t331
	bpt
	br	n332
t331:	bpt
n332:
	ccc
	.word	^o266
	blos	t333
	bpt
	br	n334
t333:	bpt
n334:
	ccc
	.word	^o267
	blos	t335
	bpt
	br	n336
t335:	bpt
n336:
	ccc
	.word	^o270
	blos	t337
	bpt
	br	n338
t337:	bpt
n338:
	ccc
	.word	^o271
	blos	t339
	bpt
	br	n340
t339:	bpt
n340:
	ccc
	.word	^o272
	blos	t341
	bpt
	br	n342
t341:	bpt
n342:
	ccc
	.word	^o273
	blos	t343
	bpt
	br	n344
t343:	bpt
n344:
	ccc
	.word	^o274
	blos	t345
	bpt
	br	n346
t345:	bpt
n346:
	ccc
	.word	^o275
	blos	t347
	bpt
	br	n348
t347:	bpt
n348:
	ccc
	.word	^o276
	blos	t349
	bpt
	br	n350
t349:	bpt
n350:
	ccc
	.word	^o277
	blos	t351
	bpt
	br	n352
t351:	bpt
n352:
	ccc
	bvc	t353
	bpt
	br	n354
t353:	bpt
n354:
	ccc
	.word	^o261
	bvc	t355
	bpt
	br	n356
t355:	bpt
n356:
	ccc
	.word	^o262
	bvc	t357
	bpt
	br	n358
t357:	bpt
n358:
	ccc
	.word	^o263
	bvc	t359
	bpt
	br	n360
t359:	bpt
n360:
	ccc
	.word	^o264
	bvc	t361
	bpt
	br	n362
t361:	bpt
n362:
	ccc
	.word	^o265
	bvc	t363
	bpt
	br	n364
t363:	bpt
n364:
	ccc
	.word	^o266
	bvc	t365
	bpt
	br	n366
t365:	bpt
n366:
	ccc
	.word	^o267
	bvc	t367
	bpt
	br	n368
t367:	bpt
n368:
	ccc
	.word	^o270
	bvc	t369
	bpt
	br	n370
t369:	bpt
n370:
	ccc
	.word	^o271
	bvc	t371
	bpt
	br	n372
t371:	bpt
n372:
	ccc
	.word	^o272
	bvc	t373
	bpt
	br	n374
t373:	bpt
n374:
	ccc
	.word	^o273
	bvc	t375
	bpt
	br	n376
t375:	bpt
n376:
	ccc
	.word	^o274
	bvc	t377
	bpt
	br	n378
t377:	bpt
n378:
	ccc
	.word	^o275
	bvc	t379
	bpt
	br	n380
t379:	bpt
n380:
	ccc
	.word	^o276
	bvc	t381
	bpt
	br	n382
t381:	bpt
n382:
	ccc
	.word	^o277
	bvc	t383
	bpt
	br	n384
t383:	bpt
n384:
	ccc
	bvs	t385
	bpt
	br	n386
t385:	bpt
n386:
	ccc
	.word	^o261
	bvs	t387
	bpt
	br	n388
t387:	bpt
n388:
	ccc
	.word	^o262
	bvs	t389
	bpt
	br	n390
t389:	bpt
n390:
	ccc
	.word	^o263
	bvs	t391
	bpt
	br	n392
t391:	bpt
n392:
	ccc
	.word	^o264
	bvs	t393
	bpt
	br	n394
t393:	bpt
n394:
	ccc
	.word	^o265
	bvs	t395
	bpt
	br	n396
t395:	bpt
n396:
	ccc
	.word	^o266
	bvs	t397
	bpt
	br	n398
t397:	bpt
n398:
	ccc
	.word	^o267
	bvs	t399
	bpt
	br	n400
t399:	bpt
n400:
	ccc
	.word	^o270
	bvs	t401
	bpt
	br	n402
t401:	bpt
n402:
	ccc
	.word	^o271
	bvs	t403
	bpt
	br	n404
t403:	bpt
n404:
	ccc
	.word	^o272
	bvs	t405
	bpt
	br	n406
t405:	bpt
n406:
	ccc
	.word	^o273
	bvs	t407
	bpt
	br	n408
t407:	bpt
n408:
	ccc
	.word	^o274
	bvs	t409
	bpt
	br	n410
t409:	bpt
n410:
	ccc
	.word	^o275
	bvs	t411
	bpt
	br	n412
t411:	bpt
n412:
	ccc
	.word	^o276
	bvs	t413
	bpt
	br	n414
t413:	bpt
n414:
	ccc
	.word	^o277
	bvs	t415
	bpt
	br	n416
t415:	bpt
n416:
	ccc
	bcc	t417
	bpt
	br	n418
t417:	bpt
n418:
	ccc
	.word	^o261
	bcc	t419
	bpt
	br	n420
t419:	bpt
n420:
	ccc
	.word	^o262
	bcc	t421
	bpt
	br	n422
t421:	bpt
n422:
	ccc
	.word	^o263
	bcc	t423
	bpt
	br	n424
t423:	bpt
n424:
	ccc
	.word	^o264
	bcc	t425
	bpt
	br	n426
t425:	bpt
n426:
	ccc
	.word	^o265
	bcc	t427
	bpt
	br	n428
t427:	bpt
n428:
	ccc
	.word	^o266
	bcc	t429
	bpt
	br	n430
t429:	bpt
n430:
	ccc
	.word	^o267
	bcc	t431
	bpt
	br	n432
t431:	bpt
n432:
	ccc
	.word	^o270
	bcc	t433
	bpt
	br	n434
t433:	bpt
n434:
	ccc
	.word	^o271
	bcc	t435
	bpt
	br	n436
t435:	bpt
n436:
	ccc
	.word	^o272
	bcc	t437
	bpt
	br	n438
t437:	bpt
n438:
	ccc
	.word	^o273
	bcc	t439
	bpt
	br	n440
t439:	bpt
n440:
	ccc
	.word	^o274
	bcc	t441
	bpt
	br	n442
t441:	bpt
n442:
	ccc
	.word	^o275
	bcc	t443
	bpt
	br	n444
t443:	bpt
n444:
	ccc
	.word	^o276
	bcc	t445
	bpt
	br	n446
t445:	bpt
n446:
	ccc
	.word	^o277
	bcc	t447
	bpt
	br	n448
t447:	bpt
n448:
	ccc
	bcs	t449
	bpt
	br	n450
t449:	bpt
n450:
	ccc
	.word	^o261
	bcs	t451
	bpt
	br	n452
t451:	bpt
n452:
	ccc
	.word	^o262
	bcs	t453
	bpt
	br	n454
t453:	bpt
n454:
	ccc
	.word	^o263
	bcs	t455
	bpt
	br	n456
t455:	bpt
n456:
	ccc
	.word	^o264
	bcs	t457
	bpt
	br	n458
t457:	bpt
n458:
	ccc
	.word	^o265
	bcs	t459
	bpt
	br	n460
t459:	bpt
n460:
	ccc
	.word	^o266
	bcs	t461
	bpt
	br	n462
t461:	bpt
n462:
	ccc
	.word	^o267
	bcs	t463
	bpt
	br	n464
t463:	bpt
n464:
	ccc
	.word	^o270
	bcs	t465
	bpt
	br	n466
t465:	bpt
n466:
	ccc
	.word	^o271
	bcs	t467
	bpt
	br	n468
t467:	bpt
n468:
	ccc
	.word	^o272
	bcs	t469
	bpt
	br	n470
t469:	bpt
n470:
	ccc
	.word	^o273
	bcs	t471
	bpt
	br	n472
t471:	bpt
n472:
	ccc
	.word	^o274
	bcs	t473
	bpt
	br	n474
t473:	bpt
n474:
	ccc
	.word	^o275
	bcs	t475
	bpt
	br	n476
t475:	bpt
n476:
	ccc
	.word	^o276
	bcs	t477
	bpt
	br	n478
t477:	bpt
n478:
	ccc
	.word	^o277
	bcs	t479
	bpt
	br	n480
t479:	bpt
n480:
; ---- the longest displacements: +127 and -128 words
	br	FWD
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
FWD:	bpt
	br	BKX
BK:	bpt
	br	BKD
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240
BKX:	br	BK
BKD:
; ---- JMP: each mode but register; J1 logs and returns through R5
; (R1)
	mov	#r481, r5
	mov	#J1, r1
	jmp	(r1)
r481:
; (R1)+
	mov	#r482, r5
	mov	#J1, r1
	jmp	(r1)+
r482:
; @(R1)+
	mov	#r483, r5
	mov	#JP, r1
	jmp	@(r1)+
r483:
; -(R1)
	mov	#r484, r5
	mov	#J1+2, r1
	jmp	-(r1)
r484:
; @-(R1)
	mov	#r485, r5
	mov	#JP+2, r1
	jmp	@-(r1)
r485:
; X(R1)
	mov	#r486, r5
	mov	#J1-^x100, r1
	jmp	^x100(r1)
r486:
; @X(R1)
	mov	#r487, r5
	mov	#JP+^x40, r1
	jmp	@-^x40(r1)
r487:
; relative
	mov	#r488, r5
	clr	r1
	jmp	J1
r488:
; relative deferred
	mov	#r489, r5
	clr	r1
	jmp	@JP
r489:
; absolute
	mov	#r490, r5
	clr	r1
	jmp	@#J1
r490:
; JMP (PC)+: to the word after it
	jmp	(pc)+
	bpt
; ---- JSR, RTS
	mov	#^x1111, r5
	jsr	pc, S1
	bpt
	jsr	r5, S2
	.word	^x1234
	bpt
	mov	#JP+2, r1
	jsr	r1, @(r1)+
	bpt
	mov	#SR, r1
	jsr	pc, (r1)
	bpt
; ---- SOB
	mov	#3, r1
	clr	r2
SB1:	inc	r2
	sob	r1, SB1
	bpt
	mov	#1, r1
SB2:	sob	r1, SB2
	bpt
	mov	#2, r1
	clr	r2
SB3:	inc	r2
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240, ^o240
	.word	^o240, ^o240, ^o240, ^o240, ^o240
	sob	r1, SB3
	bpt
; ---- MOV, ADD to PC; MOV PC
	mov	#MP1, pc
	bpt
MP1:	add	#4, pc
	bpt
	bpt
	mov	pc, r1
	bpt
; ---- RTI, RTT: PC and PSW<4:0> popped
	mov	#^o17, -(sp)
	mov	#i491, -(sp)
	rti
	bpt
i491:	bpt
	mov	#^o177740, -(sp)
	mov	#i492, -(sp)
	rtt
	bpt
i492:	bpt
	mov	#^o177757, -(sp)
	mov	#i493, -(sp)
	rti
	bpt
i493:	bpt
	mov	#^o5, -(sp)
	mov	#i494, -(sp)
	rtt
	bpt
i494:	bpt
; ---- trace
; RTI and RTT with T in the PSW popped: the next instruction runs, the
; trace comes before the one after it (the handler then clears T)
	mov	#^o20, -(sp)
	mov	#i495, -(sp)
	rti
i495:	mov	#1, r0
	mov	#2, r0
	mov	#3, r0
	bpt
	mov	#^o20, -(sp)
	mov	#i496, -(sp)
	rtt
i496:	mov	#1, r0
	mov	#2, r0
	mov	#3, r0
	bpt
; REI with T (EMT 376): three instructions traced, a BPT with T set
; (the fault first, TP clear in its PSL) among them
	emt	^o376
	mov	#1, r1
	bpt
	mov	#2, r1
	mov	#3, r1
	mov	#4, r1
	bpt
; RTI that sets T, then an RTI with T at its start popping a PSW without
; it: the second is traced (PSL T clear), at TR2
	mov	#0, -(sp)
	mov	#TR2, -(sp)
	mov	#^o20, -(sp)
	mov	#TR1, -(sp)
	rti
TR1:	rti
TR2:	bpt
	emt	^o377
; the subroutines and the jump targets
S1:	mov	#^x2222, r5
	rts	pc
S2:	mov	(r5)+, r4
	rts	r5
SR:	mov	sp, r2
	rts	pc
J1:	bpt
	jmp	(r5)
J2:	bpt
	rts	r1
JP:	.word	J1, J2, J1
	.vax
; the handlers, after the compat code; mkboard.py (software/mmutest.bin)
; appends its code and table after them, out of the way of the test
	.org	^xA000
; the compatibility mode exception: BPT is stepped over, EMT 377 stops,
; EMT 376 starts the trace of part T (REI with PSL<T>: R9 traces)
	.align	4
cmexc:	movl	(sp)+, r10		; the code
	jsb	log
	cmpl	r10, #1			; BPT: on
	bneq	cmx
	addl2	#2, (sp)
	rei
cmx:	movzwl	@(sp), r10
	cmpl	r10, #^o104376		; EMT 376: REI to the next word, T set
	bneq	cmy
	addl2	#2, (sp)
	bisl2	#^x10, 4(sp)
	movl	#3, r9
	rei
cmy:	halt				; EMT 377: the end

; trace fault: logged; after R9 of them T is cleared
	.align	4
trace:	movl	#^x28, r10
	jsb	log
	sobgtr	r9, tr1
	bicl2	#^x10, 4(sp)
tr1:	rei

; log r10, the PC and PSL of the frame (at 4(sp), after the JSB) and R0-R6
log:	movl	r10, (r11)+
	movl	4(sp), (r11)+
	movl	8(sp), (r11)+
	movl	r0, (r11)+
	movl	r1, (r11)+
	movl	r2, (r11)+
	movl	r3, (r11)+
	movl	r4, (r11)+
	movl	r5, (r11)+
	movl	r6, (r11)+
	rsb

	.align	4
unexp:	movl	#^xBAD, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	halt
