#===============================================================================
#  Pokemon Pathways Multiplayer Client - Remote Player Sprite (STABLE v2.1)
#
#  CRITICAL FIX: This file addresses Root Causes #1, #2, and #4.
#
#  Root Cause 1 — Unsafe set_character_bitmap:
#    Sprite_Character#initialize calls set_character_bitmap which calls
#    GameData::Character.check_graphic_file → CachedBitmap.new. Missing charset
#    files cause exceptions during Sprite_MP_RemotePlayer.new.
#  Fix: Override set_character_bitmap with full exception handling. If the
#    charset file cannot be loaded, create a colored placeholder bitmap.
#
#  Root Cause 2 — Remote sprites never updated:
#    Sprites were stored in @remote_sprites but never added to
#    Spriteset_Map's @character_sprites, and .update was never called.
#  Fix: MP_OverworldManager#update now calls update_safe on every remote sprite.
#
#  Root Cause 4 — @character not cleared on dispose:
#    dispose set @mp_character=nil but left @character (from parent) intact.
#  Fix: dispose now explicitly clears @character and all references.
#
#  ARCHITECTURE:
#    Inherits Sprite_Character for full PE integration (shadows, z-depth,
#    bush depth, animation). Overrides only the dangerous methods.
#===============================================================================

class Sprite_MP_RemotePlayer < Sprite_Character
  # Static cache of verified charset files (avoids repeated disk checks)
  @@verified_charsets = {}
  @@placeholder_bitmap_cache = {}

  # Placeholder colors by player ID for visual distinction
  PLACEHOLDER_COLORS = [
    [255, 80, 80], [80, 255, 80], [80, 80, 255], [255, 255, 80],
    [255, 80, 255], [80, 255, 255], [255, 160, 80], [160, 80, 255]
  ].freeze

  # @param viewport [Viewport]            the map's tile viewport
  # @param character [MP_Game_RemotePlayer]
  def initialize(viewport, character)
    # CRITICAL: Validate viewport BEFORE calling super.
    # Sprite_Character assumes viewport is valid and may crash if not.
    if viewport.nil? || !viewport.respond_to?(:disposed?)
      raise ArgumentError, "Sprite_MP_RemotePlayer: viewport is nil or invalid"
    end
    if viewport.disposed?
      raise ArgumentError, "Sprite_MP_RemotePlayer: viewport is disposed"
    end
    if character.nil?
      raise ArgumentError, "Sprite_MP_RemotePlayer: character is nil"
    end

    # DO NOT call super yet — we need to intercept set_character_bitmap
    # Store refs locally, then call super with rescue
    @mp_character = character
    @bitmap_load_failed = false
    @placeholder_bitmap = nil
    @frame_count = 0

    mp_log("SPRITE: init begin id=#{character.mp_id} charset=#{character.character_name}") if defined?(mp_log)

    begin
      super(viewport, character)
    rescue => e
      mp_log_exception("SPRITE: super() failed id=#{character.mp_id}", e) if defined?(mp_log_exception)
      # Emergency: create minimal sprite manually
      @character = character
      initialize_basic_sprite(viewport)
    end

    mp_log("SPRITE: init done id=#{character.mp_id} oid=#{self.object_id}") if defined?(mp_log)
  end

  # ─── CRITICAL OVERRIDES ────────────────────────────────────────────────────

  # OVERRIDE: Wrap the dangerous bitmap loading in full exception handling.
  # If the charset file cannot be loaded, create a placeholder bitmap.
  def set_character_bitmap
    return unless @character

    char_name = @character.character_name.to_s
    mp_log("SPRITE: set_character_bitmap '#{char_name}' id=#{@mp_character&.mp_id}") if defined?(mp_log)

    if char_name.empty?
      create_placeholder_bitmap
      return
    end

    # PHASE 1 SAFE MODE: skip all bitmap loading, use placeholder
    if MP_ClientConfig::PLACEHOLDER_ON_MISSING_CHARSET && !charset_file_exists?(char_name)
      mp_log("SPRITE: charset '#{char_name}' not found, using placeholder") if defined?(mp_log)
      create_placeholder_bitmap
      return
    end

    begin
      # Attempt normal PE charset loading
      if respond_to?(:tileset_bitmap) && @tile_id && @tile_id >= 384
        self.bitmap = tileset_bitmap(@tile_id)
        @cw = 32
        @ch = 32
      else
        # PE v19.1 path
        bitmap_file = GameData::Character.check_graphic_file("Graphics/Characters/", char_name) rescue nil
        if bitmap_file.nil? || !FileTest.exist?(bitmap_file)
          if MP_ClientConfig::PLACEHOLDER_ON_MISSING_CHARSET
            create_placeholder_bitmap
            return
          else
            bitmap_file = GameData::Character.check_graphic_file("Graphics/Characters/", char_name)
          end
        end
        self.bitmap = CachedBitmap.new(bitmap_file)
        @cw = [self.bitmap.width / 4, 1].max
        @ch = [self.bitmap.height / 4, 1].max
      end
      self.ox = @cw / 2
      self.oy = @ch
      @bitmap_load_failed = false
      @placeholder_bitmap = nil
    rescue => e
      mp_log_exception("SPRITE: set_character_bitmap FAILED '#{char_name}'", e) if defined?(mp_log_exception)
      if MP_ClientConfig::PLACEHOLDER_ON_MISSING_CHARSET
        create_placeholder_bitmap
      else
        @bitmap_load_failed = true
      end
    end
  end

  # ─── Safe update called by MP_OverworldManager ─────────────────────────────

  # This is called manually by MP_OverworldManager.update every frame.
  # It replaces the normal Sprite_Character#update that would be called
  # by Spriteset_Map if we were in its @character_sprites array.
  def update_safe
    return if disposed?
    return if @character.nil?

    @frame_count += 1

    begin
      # Update position from character (critical — this is what moves the sprite!)
      self.x = @character.screen_x
      self.y = @character.screen_y
      self.z = @character.screen_z(@z)

      # Update bush depth
      if @character.respond_to?(:bush_depth)
        self.bush_depth = @character.bush_depth
      end

      # Update opacity / blend
      self.opacity = @character.opacity if @character.respond_to?(:opacity)

      # Re-check bitmap if character graphic changed
      if @character.respond_to?(:character_name) && @character.respond_to?(:tile_id)
        new_name = @character.character_name.to_s
        new_tile = @character.tile_id.to_i
        if @character_name != new_name || @tile_id != new_tile
          @tile_id = new_tile
          @character_name = new_name
          set_character_bitmap
        end
      end

      # Update animation frame (src_rect)
      update_animation

      # Update visibility
      self.visible = @character.visible if @character.respond_to?(:visible)

      # Call RPG::Sprite update (flash, etc.)
      super_update_rpg

    rescue => e
      mp_log_exception("SPRITE: update_safe id=#{@mp_character&.mp_id}", e) if defined?(mp_log_exception)
    end
  end

  # OVERRIDE: Standard update is a no-op — we use update_safe from overworld.
  # This prevents double-updates if someone adds us to a spriteset later.
  def update
    return if disposed?
    # Do NOT call super here — update_safe handles everything.
    # This prevents the parent's set_character_bitmap from being called
    # with unguarded exception handling.
  end

  # OVERRIDE: Full dispose with reference cleanup (fixes Root Cause #4)
  def dispose
    return if disposed?

    mp_log("SPRITE: dispose id=#{@mp_character&.mp_id} oid=#{self.object_id}") if defined?(mp_log)

    # Dispose name sprite first (via character reference)
    char = @mp_character
    @mp_character = nil
    @character = nil  # CRITICAL FIX: clear parent reference too!

    if char && char.respond_to?(:dispose_name_sprite)
      begin
        char.dispose_name_sprite
      rescue => e
        mp_log_exception("SPRITE: dispose name_sprite failed", e) if defined?(mp_log_exception)
      end
    end

    # Dispose placeholder bitmap
    if @placeholder_bitmap && !@placeholder_bitmap.disposed?
      begin
        @placeholder_bitmap.dispose
      rescue
        nil
      end
    end
    @placeholder_bitmap = nil

    # Call parent dispose
    begin
      super
    rescue => e
      mp_log_exception("SPRITE: super.dispose failed", e) if defined?(mp_log_exception)
    end
  end

  # ─── Private helpers ───────────────────────────────────────────────────────

  private

  # Fallback initialization when super() fails completely
  def initialize_basic_sprite(viewport)
    @character = @mp_character
    @tile_id = 0
    @character_name = @mp_character ? @mp_character.character_name.to_s : ""
    @character_hue = 0
    @cw = 32
    @ch = 32
    self.viewport = viewport
    self.ox = 16
    self.oy = 32
    create_placeholder_bitmap
  end

  def create_placeholder_bitmap
    color_idx = (@mp_character ? @mp_character.mp_id : 0) % PLACEHOLDER_COLORS.length
    rgb = PLACEHOLDER_COLORS[color_idx]
    cache_key = rgb.join(",")

    @placeholder_bitmap = @@placeholder_bitmap_cache[cache_key]
    if @placeholder_bitmap.nil? || @placeholder_bitmap.disposed?
      @placeholder_bitmap = Bitmap.new(32, 48)
      # Body rectangle
      @placeholder_bitmap.fill_rect(4, 8, 24, 32, Color.new(rgb[0], rgb[1], rgb[2]))
      # Head
      @placeholder_bitmap.fill_rect(8, 2, 16, 14, Color.new(255, 220, 180))
      # Border
      @placeholder_bitmap.fill_rect(4, 8, 24, 2, Color.new(0, 0, 0, 100))
      @placeholder_bitmap.fill_rect(4, 38, 24, 2, Color.new(0, 0, 0, 100))
      @placeholder_bitmap.fill_rect(4, 8, 2, 32, Color.new(0, 0, 0, 100))
      @placeholder_bitmap.fill_rect(26, 8, 2, 32, Color.new(0, 0, 0, 100))
      @@placeholder_bitmap_cache[cache_key] = @placeholder_bitmap
    end

    self.bitmap = @placeholder_bitmap
    @cw = 32
    @ch = 48
    self.ox = @cw / 2
    self.oy = @ch
    @bitmap_load_failed = true
  end

  def charset_file_exists?(name)
    return false if name.nil? || name.to_s.empty?
    cache_key = name.to_s
    if @@verified_charsets.key?(cache_key)
      return @@verified_charsets[cache_key]
    end
    # Check common paths
    paths = [
      "Graphics/Characters/#{cache_key}.png",
      "Graphics/Characters/#{cache_key}",
    ]
    # Also check with GameData if available
    begin
      resolved = GameData::Character.check_graphic_file("Graphics/Characters/", cache_key) rescue nil
      paths << resolved if resolved
    rescue
      nil
    end
    exists = paths.any? { |p| FileTest.exist?(p) }
    @@verified_charsets[cache_key] = exists
    exists
  rescue
    false
  end

  def update_animation
    return unless @character

    pat = 0
    if @character.respond_to?(:pattern)
      pat = @character.pattern || 0
    end

    dir = 2
    if @character.respond_to?(:direction)
      dir = @character.direction || 2
    end

    # Walking animation: cycle pattern 0-1-2-1
    walk_pat = case pat % 4
               when 0 then 1
               when 1 then 0
               when 2 then 1
               else 2
               end

    row = [(dir / 2 - 1), 0].max  # 0=down,1=left,2=right,3=up
    src_x = (walk_pat % 4) * @cw
    src_y = (row % 4) * @ch

    if self.src_rect
      self.src_rect.set(src_x, src_y, @cw, @ch)
    end
  rescue => e
    # Animation failure is non-critical; don't log every frame
  end

  def super_update_rpg
    # Call RPG::Sprite#update (grandparent), NOT Sprite_Character#update
    # This handles flash effects without re-triggering bitmap loading.
    method(:update).super_method.super_method&.bind(self)&.call rescue nil
  rescue
    nil
  end
end

