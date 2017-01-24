
  .inesprg 1   ; 1x 16KB PRG code
  .ineschr 1   ; 1x  8KB CHR data
  .inesmap 0   ; mapper 0 = NROM, no bank swapping
  .inesmir 1   ; background mirroring (horizontal scrolling)

PPU_CTRL_REG1         = $2000
;76543210
;| ||||||
;| ||||++- Base nametable address
;| ||||    (0 = $2000; 1 = $2400; 2 = $2800; 3 = $2C00)
;| |||+--- VRAM address increment per CPU read/write of PPUDATA
;| |||     (0: increment by 1, going across; 1: increment by 32, going down)
;| ||+---- Sprite pattern table address for 8x8 sprites (0: $0000; 1: $1000)
;| |+----- Background pattern table address (0: $0000; 1: $1000)
;| +------ Sprite size (0: 8x8; 1: 8x16)
;|
;+-------- Generate an NMI at the start of the
;          vertical blanking interval (0: off; 1: on)

PPU_CTRL_REG2         = $2001
PPU_STATUS            = $2002
PPU_SPR_ADDR          = $2003
PPU_SPR_DATA          = $2004
PPU_SCROLL_REG        = $2005
PPU_ADDRESS           = $2006
PPU_DATA              = $2007

;Sprite:
;  76543210
;  |||   ||
;  |||   ++- Palette (4 to 7) of sprite
;  |||
;  ||+------ Priority (0: in front of background; 1: behind background)
;  |+------- Flip sprite horizontally
;  +-------- Flip sprite vertically

CONTROLLER1_PORT          = $4016
CONTROLLER2_PORT          = $4017

BUTTON_A      = %10000000
BUTTON_B      = %01000000
BUTTON_SELECT = %00100000
BUTTON_START  = %00010000
BUTTON_UP     = %00001000
BUTTON_DOWN   = %00000100
BUTTON_LEFT   = %00000010
BUTTON_RIGHT  = %00000001

p1_buttons   .rs 1
p1_sprite_y = $0200
p1_sprite_tile = $0201
p1_sprite_attribute = $0202
p1_sprite_x = $0203
P1_SPEED = %00000010
p1_direction_y .rs 1
p1_vertical_velocity .rs 1
p1_on_ground .rs 1
JUMP_VELOCITY = %00001000  ;2s compliment Note gravity gets applied to this even before y is updated
GRAVITY = %00000001
MAX_FALL_SPEED = %00000111

p1_current_sprite_index .rs 1 ; TODO this should be calculatable from the sprite itself
  .rsset $0000 ; zero page important stuff
collision_low  .rs 1   ; Don't know a better way to do this at least yet
collision_high .rs 1

  .rsset $0300
collision_map .rs 960 ; This should be 960, but keep it simple for now


;;;;;;;;;;;;;;;

  .bank 0
  .org $C000

RESET:
  SEI          ; disable IRQs
  CLD          ; disable decimal mode
  LDX #$40
  STX $4017    ; disable APU frame IRQ
  LDX #$FF
  TXS          ; Set up stack
  INX          ; now X = 0
  STX PPU_CTRL_REG1    ; disable NMI
  STX PPU_CTRL_REG2    ; disable rendering
  STX $4010    ; disable DMC IRQs

vblankwait1:       ; First wait for vblank to make sure PPU is ready
  BIT PPU_STATUS
  BPL vblankwait1

clrmem:
  LDA #$00
  STA $0000, x
  STA $0100, x
  STA $0200, x
  STA $0400, x
  STA $0500, x
  STA $0600, x
  STA $0700, x
  LDA #$FE
  STA $0300, x
  INX
  BNE clrmem

vblankwait2:      ; Second wait for vblank, PPU is ready after this
  BIT PPU_STATUS
  BPL vblankwait2

InitState:
  LDA #$00
  STA p1_current_sprite_index
  STA p1_vertical_velocity
  STA p1_direction_y
  STA p1_on_ground

  JSR LoadP1
  JSR LoadBackground
  JSR LoadAttributes
  JSR LoadPalettes

  LDA #%00011110   ; enable sprites, enable background, no clipping on left side
  STA PPU_CTRL_REG2

  LDA #%10010000    ; want both background and sprites to use graphic table 0
  STA PPU_CTRL_REG1

Forever:
  JMP Forever

NMI:
  LDA #$00
  STA PPU_SPR_ADDR       ; set the low byte (00) of the RAM address
  LDA #$02
  STA $4014       ; set the high byte (02) of the RAM address, start the transfer
  JSR ReadController1
  JSR MoveP1

  LDA #$00
  STA PPU_SCROLL_REG
  STA PPU_SCROLL_REG

  RTI

; ###################
; Load p1 sprite onto the screen
; ###################
LoadP1:
  LDA #$A0 ; for now initialize to random values
  STA p1_sprite_y
  STA p1_sprite_x
  LDA #$00
  STA p1_sprite_attribute
  LDA p1_run
  LDX #$01
  STA p1_sprite_tile
  RTS

LoadAttributes:
  LDA $2002             ; read PPU status to reset the high/low latch
  LDA #$23
  STA PPU_ADDRESS       ; write the high byte of $23C0 address
  LDA #$C0
  STA PPU_ADDRESS       ; write the low byte of $23C0 address
  LDX #$00              ; start out at 0
LoadAttributeLoop:
  LDA attribute, x      ; normally load data from address (attribute + the value in x)
  STA $2007             ; write to PPU
  INX                   ; X = X + 1
  CPX #$40              ; 64 total bytes necessary to do full screen
  BNE LoadAttributeLoop
  RTS

LoadPalettes:
  LDA PPU_STATUS
  LDA #$3F
  STA PPU_ADDRESS
  LDA #$00
  STA PPU_ADDRESS
  LDX #$00
LoadPalettesLoop:
  LDA palette, x        ; load data from address (palette + the value in x)
  STA PPU_DATA          ; write to PPU
  INX                   ; X = X + 1
  CPX #$20              ; Compare X to hex $10, decimal 16 - copying 16 bytes = 4 sprites
  BNE LoadPalettesLoop  ; Branch to LoadPalettesLoop if compare was Not Equal to zero
                        ; if compare was equal to 32, keep going down
  RTS

LoadBackground:
  LDA #low(collision_map)
  STA collision_low
  LDA #high(collision_map)
  STA collision_high
  LDA PPU_STATUS        ; read PPU status to reset the high/low latch
  LDA #$20
  STA PPU_ADDRESS       ; write the high byte of $2000 address
  LDA #$00
  STA PPU_ADDRESS       ; write the low byte of $2000 address
  LDX $00
  LDY $00
  LDA #$24
LoadBackgroundLoop:
  STA PPU_DATA
  sta [collision_low], Y
  INY
  CPY #$00
  BNE LoadBackgroundLoop
  LDA collision_high
  CLC
  ADC #$01
  STA collision_high
  LDA #$24 ; reset a back to empty background
  INX
  CPX #$03
  BNE LoadBackgroundLoop
  LDY #$00
  LDA #$00
LoadBackgroundFloorLoop:
  STA PPU_DATA
  STA [collision_low],y
  INY
  CPY #$10
  BNE LoadBackgroundFloorLoop
  LDA collision_low
  CLC
  ADC #$10
  STA collision_low
  LDA collision_high
  ADC #$00 ; only want to add the carry bit
  STA collision_high
  LDY #$00
  LDA #$24
LoadBackgroundRestLoop:        ; loaded 8x3 + 1 = 25. Have 5 left. 5x32 = 160 (or A0 in hex)
  STA PPU_DATA
  STA [collision_low],y
  INY
  CPY #$B0
  BNE LoadBackgroundRestLoop
LoadBackgroundDone:
  RTS

;TODO this is just a proof of checking nametable. will want more robust
CheckFloor:
  LDA p1_sprite_x
  LSR A
  LSR A
  LSR A              ; divide by 8
  TAX
  LDA p1_sprite_y
  LSR A
  LSR A
  LSR A              ; divide by 8
  TAY
  LDA p1_sprite_y
  AND %00000111
  BEQ CheckFloorOnExactPixel ; If we're in between tiles, want to round up (more y is lower on screen)
  INY
CheckFloorOnExactPixel:
  ; Now x, y are setup for tile num, translate them to nametable address
  ; TODO
  LDA PPU_STATUS        ; read PPU status to reset the high/low latch
  LDA #$20
  STA PPU_ADDRESS       ; write the high byte of $2000 address
  LDA #$00
  STA PPU_ADDRESS       ; write the low byte of $2000 address
  RTS

; ###################
; Move player 1 based on controller, etc
; ###################
MoveP1:
CheckP1Jump:
  LDA p1_on_ground
  CMP #$01
  BNE P1NotNewJump            ; if already moving vertically, can't jump
  LDA p1_buttons
  AND #BUTTON_A
  BEQ P1NotNewJump            ; if a is not pressed, don't jump
  LDA #$00
  STA p1_on_ground
  LDA #JUMP_VELOCITY
  STA p1_vertical_velocity
  STA p1_direction_y          ; anything but 0 means up on screen
P1NotNewJump:
  JSR MoveP1Vertically
CheckP1Direction:
  LDA p1_buttons
  AND #BUTTON_LEFT
  BEQ TryMoveP1Right
  JSR MoveP1Left
  JMP MoveP1Done
TryMoveP1Right:
  LDA p1_buttons
  AND #BUTTON_RIGHT
  BEQ MoveP1Done
  JSR MoveP1Right
  JMP MoveP1Done
MoveP1Done:
  RTS

UpdateVelocityGravity:
  LDA p1_direction_y
  CMP #$00
  BEQ UpdateVelocityGravAlreadyDown
  ; Moving up on screen
  LDA p1_vertical_velocity
  CMP #GRAVITY
  BCC UpdateVelocityGravityBigger
  ; Moving up more than gravity pulls down so just subtract
  LDA p1_vertical_velocity
  SEC
  SBC #GRAVITY
  STA p1_vertical_velocity
  JMP UpdateVelocityGravityDone
UpdateVelocityGravityBigger:
  LDA #$00
  STA p1_direction_y    ; Change direction to down
  LDA #GRAVITY
  SEC
  SBC p1_vertical_velocity
  STA p1_vertical_velocity
  JMP UpdateVelocityGravityDone
UpdateVelocityGravAlreadyDown:
  LDA p1_vertical_velocity
  CLC
  ADC #GRAVITY
  STA p1_vertical_velocity
  CMP #MAX_FALL_SPEED
  BCC UpdateVelocityGravityDone ; if not falling faster than max, we're done
  LDA #MAX_FALL_SPEED
  STA p1_vertical_velocity
UpdateVelocityGravityDone:
  RTS

UpdateP1WithYVelocity:
  LDA p1_direction_y
  CMP #$00
  BEQ UpdateP1WithYVelocityDown
  ; Moving up so subtract (because up on screen is down in y)
  LDA p1_sprite_y
  SEC
  SBC p1_vertical_velocity  ; velocity assumes up is + but y logic is backwards so subtract
  STA p1_sprite_y
  JMP UpdateP1WithYVelocityDone
UpdateP1WithYVelocityDown: ; Down in terms of the screen so add
  LDA p1_sprite_y
  CLC
  ADC p1_vertical_velocity
  STA p1_sprite_y
UpdateP1WithYVelocityDone:
  RTS

MoveP1Vertically:
  JSR UpdateVelocityGravity
  JSR UpdateP1WithYVelocity
  JMP NoVerticalCollision ; todo 

  ; Do collision detection
  LDA #low(collision_map)
  STA collision_low
  LDA #high(collision_map)
  STA collision_high
  LDA p1_sprite_y
  LSR A
  LSR A
  LSR A ; divide by 8 to remove mid pixels
  ; 32 per line, 256 per byte so 8 different sections. so mod 8 goes to low bit and divide 8 goes to high
  AND #%00000111 ; Mod 8
  CLC
  ADC collision_low
  STA collision_low
  LDA collision_high
  ADC #$00 ; add any carry to high bit
  STA collision_high
  LDA p1_sprite_y
  LSR A
  LSR A
  LSR A; divide by 8 to remove mid pixels
  LSR A
  LSR A
  LSR A ; divide by 8 because 8 tiles high x 32 tiles wide = 256 bytes, so add to high
  CLC
  ADC collision_high
  STA collision_high
  LDA p1_sprite_x
  LSR A
  LSR A
  LSR A; divide by 8
  CLC
  ADC collision_low
  STA collision_low
  LDA collision_high
  ADC #$00 ; add any carry to high bit
  STA collision_high
  LDA (collision_low)
  CMP #$00
  BEQ NoVerticalCollision   ; branch if collision map is 0
  LDA p1_sprite_x
  CMP #%10000000
  BCS NoVerticalCollision
  LDA #$01
  STA p1_on_ground
  STA p1_vertical_velocity
  LDA p1_sprite_y
  AND #%11111000            ; round off pixels to the lower 8
  STA p1_sprite_y
NoVerticalCollision:
  RTS

MoveP1Left:
  JSR UpdateP1SpriteTile

  ; Update attribute
  LDA p1_sprite_attribute
  AND #%10111111 ; make sure we're not flipped horizontally
  STA p1_sprite_attribute

  ; Update x position
  LDA p1_sprite_x
  SEC
  SBC #P1_SPEED
  STA p1_sprite_x
  RTS

MoveP1Right:
  JSR UpdateP1SpriteTile

  ; Update attribute
  LDA p1_sprite_attribute
  ORA #%01000000 ; make sure we're flipped horizontally
  STA p1_sprite_attribute

  ; Update x position
  LDA p1_sprite_x
  CLC
  ADC #P1_SPEED
  STA p1_sprite_x
  RTS

UpdateP1SpriteTile:
  ; Update run animation (TODO share with MoveP1Left)
  LDX p1_current_sprite_index
  INX
  CPX #$04  ; Sprite has 4 animation sprites
  BNE NotP1SpriteWrap2
  LDX #$00
  NotP1SpriteWrap2:
  STX p1_current_sprite_index ; Now that this is set, update the sprite itself
  LDA p1_run, x
  STA p1_sprite_tile
  RTS

; ##############################
; Put controller 1 inputs into p1_buttons
; ##############################
ReadController1:
  LDA #$01
  STA CONTROLLER1_PORT
  LDA #$00
  STA CONTROLLER1_PORT
  LDX #$08
ReadController1Loop:
  LDA CONTROLLER1_PORT
  LSR A              ; bit0 -> Carry
  ROL p1_buttons     ; bit0 <- Carry
  DEX
  BNE ReadController1Loop
  RTS

; ###############################
; Background/tile loading
; ###############################
  .bank 1
  .org $E000

palette:
  .db $0F,$30,$07,$16,$0F,$10,$00,$16,$38,$39,$3A,$3B,$3C,$3D,$3E,$0F ;background palette data
  .db $0F,$30,$07,$16,$31,$02,$38,$3C,$0F,$1C,$15,$14,$31,$02,$38,$3C ;sprite palette data

attribute:
  .db %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000 ;1x4 rows (0-3)
  .db %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000 ;2x4 rows (4-7)
  .db %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000 ;3x4 rows (8-11)
  .db %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000 ;4x4 rows (12-15)
  .db %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000 ;5x4 rows (16-19)
  .db %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000 ;6x4 rows (20-23)
  .db %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000 ;7x4 rows (24-27)
  .db %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000 ;8x4 rows (28-30)

p1_run:
  .db $00, $01, $02, $03

  .org $FFFA     ;first of the three vectors starts here
  .dw NMI        ;when an NMI happens (once per frame if enabled) the
                   ;processor will jump to the label NMI:
  .dw RESET      ;when the processor first turns on or is reset, it will jump
                   ;to the label RESET:
  .dw 0          ;external interrupt IRQ is not used

;;;;;;;;;;;;;;

  .bank 2
  .org $0000
  .incbin "graphics.chr"   ;includes 8KB graphics file from SMB1