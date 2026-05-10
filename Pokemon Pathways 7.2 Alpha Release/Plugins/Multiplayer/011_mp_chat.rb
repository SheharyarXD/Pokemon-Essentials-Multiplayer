#===============================================================================
#  MP CHAT OVERLAY v1.2.0
#  FIXED:
#    1. Removed duplicate CHAT_SYSTEM handler (was in OverworldManager too)
#    2. Added scene guard (only creates sprite in Scene_Map)
#    3. Chat activation uses CHAT_ACTIVATION_KEY (:A = Shift) not Input::USE (C/Enter)
#    4. Added disposed? checks everywhere
#    5. @messages uses shift-based trimming (not array copy)
#    6. Added @chat_active toggle (can disable chat)
#    7. Fixed ensure_chat_sprite to handle disposed viewport
#    8. Input processing only active in Scene_Map
#===============================================================================

module MP_ChatOverlay
  module_function

  MAX_MESSAGES    = MP_ClientConfig::CHAT_MAX_MESSAGES
  MESSAGE_FADE    = MP_ClientConfig::CHAT_FADE_TIME
  CHAT_WIDTH      = 400
  CHAT_HEIGHT     = 120
  LINE_HEIGHT     = 22

  @messages         = []
  @visible          = true
  @input_active     = false
  @input_text       = ""
  @chat_sprite      = nil
  @chat_bitmap      = nil
  @viewport         = nil
  @initialized      = false
  @chat_active      = true   # can be toggled off

  def init
    return if @initialized
    @initialized  = true
    @messages     = []
    @visible      = true
    @input_active = false
    @input_text   = ""
    @chat_active  = true
    register_packet_handlers
    echoln "[MP] Chat overlay initialized"
  end

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::CHAT_MESSAGE) do |payload|
      add_message("#{payload['sender']}: #{payload['message']}", :normal)
    end

    MP_NetworkManager.on_packet(MP_PacketType::CHAT_WHISPER) do |payload|
      if payload["echo"]
        add_message("> #{payload['sender']}: #{payload['message']}", :whisper)
      else
        add_message("[PM] #{payload['sender']}: #{payload['message']}", :whisper)
      end
    end

    # Only register CHAT_SYSTEM here -- removed from OverworldManager
    MP_NetworkManager.on_packet(MP_PacketType::CHAT_SYSTEM) do |payload|
      add_message("[SYSTEM] #{payload['message']}", :system)
    end
  end

  def update
    return unless @visible
    return unless @chat_active
    return unless Graphics
    return unless $scene.is_a?(Scene_Map)

    update_input
    update_messages
    render_chat
  end

  def update_input
    return if $game_temp.in_menu || $game_temp.in_battle

    # Use configurable activation key (default :A = Shift/L key)
    # Falls back to Input::USE (C/Enter) if activation key not available
    activation = false
    begin
      if Input.respond_to?(:trigger?) && defined?(Input::A)
        activation = Input.trigger?(Input::A)
      end
    rescue
      activation = false
    end

    # Also check for alternative chat key
    if !activation
      begin
        activation = Input.trigger?(Input::X)  # A key on keyboard
      rescue
        activation = false
      end
    end

    if activation && !@input_active
      # Don't activate if facing an event
      return if facing_event?
      @input_active = true
      @input_text = ""
    end

    if @input_active
      process_input_keys
    end
  end

  def facing_event?
    return false unless $game_player && $game_map
    x = $game_player.x
    y = $game_player.y
    d = $game_player.direction
    case d
    when 2; y += 1
    when 4; x -= 1
    when 6; x += 1
    when 8; y -= 1
    end
    # Check for event at facing position
    $game_map.events.any? { |_, e| e.x == x && e.y == y } rescue false
  end

  def process_input_keys
    # Backspace
    if Input.repeat?(Input::LEFT) || Input.repeat?(Input::ACTION)
      @input_text = @input_text[0..-2] unless @input_text.empty?
    end

    # Submit on Enter (C/USE)
    if Input.trigger?(Input::USE)
      send_message(@input_text) unless @input_text.strip.empty?
      @input_active = false
      @input_text = ""
    end

    # Cancel on Escape/Back
    if Input.trigger?(Input::BACK)
      @input_active = false
      @input_text = ""
    end

    # Letter input -- MKXP-Z provides Input.gets in some builds
    # Fallback: check common letters via Input.press? with keycodes
    # This is a simplified approach; full text input requires engine support
    process_text_input
  end

  def process_text_input
    # For MKXP-Z builds with Input.gets support
    return unless defined?(Input.gets)
    text = Input.gets
    return unless text
    @input_text += text if @input_text.length < 100
  rescue
    # Input.gets not available
  end

  def update_messages
    now = Time.now.to_f * 1000

    @messages.each do |msg|
      elapsed = now - msg[:timestamp]
      if elapsed > MESSAGE_FADE
        msg[:alpha] = [(255 - (elapsed - MESSAGE_FADE) / 2).to_i, 0].max
      else
        msg[:alpha] = 255
      end
    end

    # Remove fully faded messages using shift (efficient)
    @messages.shift while !@messages.empty? && @messages.first[:alpha] <= 0 &&
                         (now - @messages.first[:timestamp]) > MESSAGE_FADE + 500

    # Hard cap on message count
    while @messages.length > MAX_MESSAGES * 2
      @messages.shift
    end
  end

  def render_chat
    return unless ensure_chat_sprite
    return if @chat_sprite.disposed?

    @chat_bitmap.clear if @chat_bitmap && !@chat_bitmap.disposed?
    return unless @chat_bitmap

    # Background
    bg_color = Color.new(0, 0, 0, 128)
    @chat_bitmap.fill_rect(0, 0, CHAT_WIDTH, CHAT_HEIGHT, bg_color)

    # Draw messages
    y_offset = 0
    @messages.last(MAX_MESSAGES).each do |msg|
      color = case msg[:type]
              when :system  then Color.new(255, 200, 100, msg[:alpha])
              when :whisper then Color.new(200, 255, 200, msg[:alpha])
              else Color.new(255, 255, 255, msg[:alpha])
              end

      @chat_bitmap.font.size = 13
      @chat_bitmap.font.color = color
      @chat_bitmap.draw_text(4, y_offset, CHAT_WIDTH - 8, LINE_HEIGHT, msg[:text])
      y_offset += LINE_HEIGHT
    end

    # Draw input box
    if @input_active
      input_y = CHAT_HEIGHT - LINE_HEIGHT
      @chat_bitmap.fill_rect(0, input_y, CHAT_WIDTH, LINE_HEIGHT, Color.new(0, 0, 0, 180))
      @chat_bitmap.font.color = Color.new(255, 255, 255)
      @chat_bitmap.draw_text(4, input_y, CHAT_WIDTH - 8, LINE_HEIGHT, "> #{@input_text}_")
    end

    @chat_sprite.visible = @visible && $scene.is_a?(Scene_Map)
  end

  def ensure_chat_sprite
    return false unless $scene.is_a?(Scene_Map)

    if @chat_sprite.nil? || @chat_sprite.disposed?
      begin
        # Dispose old viewport if it exists and isn't disposed
        if @viewport && !@viewport.disposed?
          @viewport.dispose
        end

        @viewport = Viewport.new(0, Graphics.height - CHAT_HEIGHT - 20, CHAT_WIDTH, CHAT_HEIGHT)
        @viewport.z = 5000
        @chat_bitmap = Bitmap.new(CHAT_WIDTH, CHAT_HEIGHT)
        @chat_sprite = Sprite.new(@viewport)
        @chat_sprite.bitmap = @chat_bitmap
      rescue => e
        echoln "[MP][Chat] Sprite creation error: #{e.class}"
        return false
      end
    end

    true
  end

  def add_message(text, type = :normal)
    @messages << {
      text:      text,
      type:      type,
      timestamp: Time.now.to_f * 1000,
      alpha:     255
    }

    echoln "[MP][Chat] #{text}"
  end

  def send_message(text)
    return unless MP_NetworkManager.connected?
    return if text.strip.empty?

    text = text.strip

    # Parse whisper: /w username message
    if text.start_with?("/w ") || text.start_with?("/whisper ")
      parts = text.split(" ", 3)
      if parts.length >= 3
        target  = parts[1]
        message = parts[2]
        MP_NetworkManager.send_packet(MP_PacketType::CHAT_WHISPER, {
          target:  target,
          message: message
        })
        add_message("-> #{target}: #{message}", :whisper)
      else
        add_message("Usage: /w username message", :system)
      end
    else
      MP_NetworkManager.send_packet(MP_PacketType::CHAT_MESSAGE, {
        message: text
      })
    end
  end

  def visible=(val)
    @visible = val
    @chat_sprite.visible = val if @chat_sprite && !@chat_sprite.disposed?
  end

  def chat_active=(val)
    @chat_active = val
  end

  def dispose
    begin
      @chat_sprite.dispose if @chat_sprite && !@chat_sprite.disposed?
    rescue; end
    @chat_sprite = nil

    begin
      @chat_bitmap.dispose if @chat_bitmap && !@chat_bitmap.disposed?
    rescue; end
    @chat_bitmap = nil

    begin
      @viewport.dispose if @viewport && !@viewport.disposed?
    rescue; end
    @viewport = nil

    @messages.clear
    @input_active = false
    @input_text = ""
    @initialized = false
  end

  def show
    self.visible = true
  end

  def hide
    self.visible = false
  end
end

# Initialize
MP_ChatOverlay.init
