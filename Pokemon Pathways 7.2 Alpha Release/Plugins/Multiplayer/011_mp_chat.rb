#===============================================================================
#  Pokemon Pathways Multiplayer Client - Chat Overlay (STABLE v2.1)
#
#  FIXES v2.1:
#   * All sprite operations wrapped in begin/rescue
#   * Viewport validated before every use
#   * Bitmap operations guarded against disposed objects
#   * Lazy sprite creation deferred until first message
#   * dispose_sprites handles partially initialized state
#===============================================================================

module MP_ChatOverlay
  module_function

  MAX_MESSAGES      = 5
  MESSAGE_FADE_MS   = 8000
  CHAT_WIDTH        = 400
  CHAT_HEIGHT       = 110
  LINE_HEIGHT       = 22
  CHAT_X            = 4
  CHAT_Y_OFFSET     = 24

  @messages     = []
  @chat_sprite  = nil
  @chat_bitmap  = nil
  @viewport     = nil
  @initialized  = false

  def init
    return if @initialized
    @initialized = true
    @messages    = []
    register_packet_handlers
    mp_log("CHAT: initialized v2.1") if defined?(mp_log)
  end

  def leave_scene_map
    dispose_sprites
    @messages.clear
    mp_log("CHAT: leave_scene_map") if defined?(mp_log)
  end

  def dispose
    leave_scene_map
    @initialized = false
    mp_log("CHAT: disposed") if defined?(mp_log)
  end

  def dispose_sprites
    begin
      if @chat_sprite && @chat_sprite.respond_to?(:disposed?) && !@chat_sprite.disposed?
        @chat_sprite.dispose
      end
    rescue => e
      mp_log_exception("CHAT: sprite dispose", e) if defined?(mp_log_exception)
    end
    begin
      if @chat_bitmap && @chat_bitmap.respond_to?(:disposed?) && !@chat_bitmap.disposed?
        @chat_bitmap.dispose
      end
    rescue => e
      mp_log_exception("CHAT: bitmap dispose", e) if defined?(mp_log_exception)
    end
    begin
      if @viewport && @viewport.respond_to?(:disposed?) && !@viewport.disposed?
        @viewport.dispose
      end
    rescue => e
      mp_log_exception("CHAT: viewport dispose", e) if defined?(mp_log_exception)
    end
    @chat_sprite = nil
    @chat_bitmap = nil
    @viewport    = nil
  end

  def update
    return unless @initialized
    begin
      check_chat_input
      update_message_alpha
      render_chat
    rescue => e
      mp_log_exception("CHAT: update", e) if defined?(mp_log_exception)
    end
  end

  def add_message(text, type = :normal)
    @messages << {
      text:      text.to_s[0, 100],
      type:      type,
      timestamp: Time.now.to_f * 1000,
      alpha:     255
    }
    @messages.shift if @messages.length > MAX_MESSAGES * 2
    mp_log("CHAT: #{text}") if defined?(mp_log)
  rescue => e
    mp_log_exception("CHAT: add_message", e) if defined?(mp_log_exception)
  end

  def send_chat_message(text)
    return unless MP_NetworkManager.connected?
    text = text.to_s.strip
    return if text.empty?

    if text.start_with?("/w ") || text.start_with?("/whisper ")
      parts = text.split(" ", 3)
      if parts.length >= 3
        MP_NetworkManager.send_packet(MP_PacketType::CHAT_WHISPER, {
          "target"  => parts[1].to_s,
          "message" => parts[2].to_s
        })
        add_message("-> #{parts[1]}: #{parts[2]}", :whisper)
      else
        add_message("Usage: /w <player> <message>", :system)
      end
    else
      MP_NetworkManager.send_packet(MP_PacketType::CHAT_MESSAGE, { "message" => text })
    end
  rescue => e
    mp_log_exception("CHAT: send_chat_message", e) if defined?(mp_log_exception)
  end

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::CHAT_MESSAGE) do |p|
      begin
        add_message("#{p['sender']}: #{p['message']}", :normal)
      rescue => e
        mp_log_exception("CHAT: CHAT_MESSAGE handler", e) if defined?(mp_log_exception)
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::CHAT_WHISPER) do |p|
      begin
        if p["echo"]
          add_message("-> #{p['to'] || '?'}: #{p['message']}", :whisper)
        else
          add_message("[PM] #{p['sender']}: #{p['message']}", :whisper)
        end
      rescue => e
        mp_log_exception("CHAT: CHAT_WHISPER handler", e) if defined?(mp_log_exception)
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::CHAT_SYSTEM) do |p|
      begin
        add_message("[*] #{p['message']}", :system)
      rescue => e
        mp_log_exception("CHAT: CHAT_SYSTEM handler", e) if defined?(mp_log_exception)
      end
    end
  end

  private

  def check_chat_input
    return if $game_temp && ($game_temp.in_menu || $game_temp.in_battle) rescue false
    return unless Input.trigger?(Input::F5) rescue false

    begin
      text = nil
      if defined?(pbMessageFreeText)
        text = pbMessageFreeText(_INTL("Chat:"), "", false, 200, Graphics.width)
      end
      send_chat_message(text) unless text.nil? || text.strip.empty?
    rescue => e
      mp_log("CHAT: input error #{e.class}: #{e.message}") if defined?(mp_log)
    end
  end

  def update_message_alpha
    now = Time.now.to_f * 1000
    @messages.each do |msg|
      elapsed = now - msg[:timestamp]
      if elapsed > MESSAGE_FADE_MS
        fade_progress = (elapsed - MESSAGE_FADE_MS) / 2000.0
        msg[:alpha] = [(255 * (1.0 - fade_progress)).to_i, 0].max
      else
        msg[:alpha] = 255
      end
    end
    @messages.reject! { |m| m[:alpha] <= 0 }
    @messages = @messages.last(MAX_MESSAGES * 2) if @messages.length > MAX_MESSAGES * 2
  rescue
    nil
  end

  def ensure_sprites
    return if @chat_sprite && !@chat_sprite.disposed?
    dispose_sprites
    begin
      screen_h  = Graphics.height rescue 384
      @viewport = Viewport.new(CHAT_X, screen_h - CHAT_HEIGHT - CHAT_Y_OFFSET,
                               CHAT_WIDTH, CHAT_HEIGHT)
      @viewport.z   = 9999
      @chat_bitmap  = Bitmap.new(CHAT_WIDTH, CHAT_HEIGHT)
      @chat_sprite  = Sprite.new(@viewport)
      @chat_sprite.bitmap = @chat_bitmap
    rescue => e
      mp_log("CHAT: sprite creation error #{e.class}: #{e.message}") if defined?(mp_log)
      @chat_sprite = nil
      @chat_bitmap = nil
      @viewport    = nil
    end
  end

  def render_chat
    recent = @messages.last(MAX_MESSAGES)
    return if recent.empty?

    ensure_sprites
    return unless @chat_sprite && !@chat_sprite.disposed?
    return unless @chat_bitmap && !@chat_bitmap.disposed?

    begin
      @chat_bitmap.clear

      used_h = recent.length * LINE_HEIGHT
      @chat_bitmap.fill_rect(0, CHAT_HEIGHT - used_h, CHAT_WIDTH, used_h,
                             Color.new(0, 0, 0, 100))

      y = CHAT_HEIGHT - used_h
      recent.each do |msg|
        color = case msg[:type]
                when :system  then Color.new(255, 200,  80, msg[:alpha])
                when :whisper then Color.new(150, 255, 150, msg[:alpha])
                else               Color.new(255, 255, 255, msg[:alpha])
                end
        @chat_bitmap.font.size  = 14
        @chat_bitmap.font.color = color
        @chat_bitmap.draw_text(4, y, CHAT_WIDTH - 8, LINE_HEIGHT, msg[:text].to_s)
        y += LINE_HEIGHT
      end

      @chat_sprite.visible = true
    rescue => e
      mp_log_exception("CHAT: render", e) if defined?(mp_log_exception)
    end
  end
end

