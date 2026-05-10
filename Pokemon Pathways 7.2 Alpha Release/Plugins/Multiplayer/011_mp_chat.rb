#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Chat Overlay
#  Small chat overlay on map screen: last 5 messages
#  Input box on Enter key, whisper with /w username
#===============================================================================

module MP_ChatOverlay
  module_function

  MAX_MESSAGES = 5
  MESSAGE_FADE_TIME = 8000  # Messages fade after 8 seconds
  CHAT_WIDTH = 400
  CHAT_HEIGHT = 120
  LINE_HEIGHT = 22

  @messages = []  # Array of { text, type, timestamp, alpha }
  @visible = false
  @input_active = false
  @input_text = ""
  @chat_sprite = nil
  @chat_bitmap = nil
  @viewport = nil
  @initialized = false
  @last_input_state = false

  def init
    return if @initialized
    @initialized = true
    @messages = []
    @visible = true
    @input_active = false
    @input_text = ""

    register_packet_handlers
  end

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::CHAT_MESSAGE) do |payload|
      add_message("#{payload['sender']}: #{payload['message']}", :normal)
    end

    MP_NetworkManager.on_packet(MP_PacketType::CHAT_WHISPER) do |payload|
      if payload["echo"]
        add_message("-> #{payload['sender']}: #{payload['message']}", :whisper)
      else
        add_message("[PM] #{payload['sender']}: #{payload['message']}", :whisper)
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::CHAT_SYSTEM) do |payload|
      add_message("[SYSTEM] #{payload['message']}", :system)
    end
  end

  def update
    return unless @visible
    return unless Graphics

    update_input
    update_messages
    render_chat
  end

  def update_input
    return if $game_temp.in_menu || $game_temp.in_battle

    # Toggle chat input on Enter/A key
    if Input.trigger?(Input::USE) && !@input_active
      # Check if we're facing another player for trade/battle interactions
      # Don't activate chat if we're near an event
      @input_active = true
      @input_text = ""
    end

    if @input_active
      # Handle text input
      process_input_keys
    end
  end

  def process_input_keys
    # Handle backspace
    if Input.repeat?(Input::LEFT) || Input.repeat?(Input::ACTION)
      @input_text = @input_text[0..-2] unless @input_text.empty?
    end

    # Submit on Enter
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

    # Character input (simplified - full text input would need more)
    # MKXP-Z provides Input.gets for text input
  end

  def update_messages
    now = Time.now.to_f * 1000
    @messages.each do |msg|
      elapsed = now - msg[:timestamp]
      if elapsed > MESSAGE_FADE_TIME
        msg[:alpha] = [(255 - (elapsed - MESSAGE_FADE_TIME) / 2).to_i, 0].max
      else
        msg[:alpha] = 255
      end
    end

    # Remove fully faded messages
    @messages.reject! { |m| m[:alpha] <= 0 && (now - m[:timestamp]) > MESSAGE_FADE_TIME + 500 }

    # Keep max messages
    @messages = @messages.last(MAX_MESSAGES) if @messages.length > MAX_MESSAGES * 2
  end

  def render_chat
    ensure_chat_sprite
    return unless @chat_bitmap

    @chat_bitmap.clear
    bg_color = Color.new(0, 0, 0, 128)
    @chat_bitmap.fill_rect(0, 0, CHAT_WIDTH, CHAT_HEIGHT, bg_color)

    # Draw messages
    y_offset = 0
    @messages.last(MAX_MESSAGES).each do |msg|
      color = case msg[:type]
              when :system then Color.new(255, 200, 100, msg[:alpha])
              when :whisper then Color.new(200, 255, 200, msg[:alpha])
              else Color.new(255, 255, 255, msg[:alpha])
              end

      @chat_bitmap.font.size = 14
      @chat_bitmap.font.color = color
      @chat_bitmap.draw_text(4, y_offset, CHAT_WIDTH - 8, LINE_HEIGHT, msg[:text])
      y_offset += LINE_HEIGHT
    end

    # Draw input box if active
    if @input_active
      input_y = CHAT_HEIGHT - LINE_HEIGHT
      @chat_bitmap.fill_rect(0, input_y, CHAT_WIDTH, LINE_HEIGHT, Color.new(0, 0, 0, 180))
      @chat_bitmap.font.color = Color.new(255, 255, 255)
      @chat_bitmap.draw_text(4, input_y, CHAT_WIDTH - 8, LINE_HEIGHT, "> #{@input_text}_")
    end

    @chat_sprite.visible = true
    @chat_sprite.bitmap = @chat_bitmap
  end

  def ensure_chat_sprite
    if @chat_sprite.nil? || @chat_sprite.disposed?
      @viewport = Viewport.new(0, Graphics.height - CHAT_HEIGHT - 20, CHAT_WIDTH, CHAT_HEIGHT)
      @viewport.z = 5000
      @chat_sprite = Sprite.new(@viewport)
      @chat_bitmap = Bitmap.new(CHAT_WIDTH, CHAT_HEIGHT)
      @chat_sprite.bitmap = @chat_bitmap
    end
  end

  def add_message(text, type = :normal)
    @messages << {
      text: text,
      type: type,
      timestamp: Time.now.to_f * 1000,
      alpha: 255
    }

    # Keep only recent messages
    @messages = @messages.last(MAX_MESSAGES * 2)

    echoln "[MP][Chat] #{text}"
  end

  def send_message(text)
    return unless MP_NetworkManager.connected?
    return if text.strip.empty?

    # Parse whisper: /w username message
    if text.start_with?("/w ") || text.start_with?("/whisper ")
      parts = text.split(" ", 3)
      if parts.length >= 3
        target = parts[1]
        message = parts[2]
        MP_NetworkManager.send_packet(MP_PacketType::CHAT_WHISPER, {
          target: target,
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
      # Server echoes back, so we don't add it locally
    end
  end

  def visible=(val)
    @visible = val
    @chat_sprite.visible = val if @chat_sprite
  end

  def dispose
    if @chat_sprite
      @chat_sprite.dispose unless @chat_sprite.disposed?
      @chat_sprite = nil
    end
    if @chat_bitmap
      @chat_bitmap.dispose unless @chat_bitmap.disposed?
      @chat_bitmap = nil
    end
    @viewport.dispose if @viewport
    @messages.clear
    @initialized = false
  end

  def show
    self.visible = true
  end

  def hide
    self.visible = false
  end
end

# Initialize chat
MP_ChatOverlay.init
