#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#
#
#  Essentials Exporter by AceOfSpadesProduc100, built from Showdown Exporter v2 for Pokémon Essentials by Cilerba and Marin, rewritten by Nuri Yuri
#
#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#
$:.push File.join(Dir.pwd, "Ruby Library 3.0.0")
require 'json'

ESSENTIALS_IV_TO_SHOWDOWN = { HP: 'HP', ATTACK: 'Atk', DEFENSE: 'Def', SPECIAL_ATTACK: 'SpA', SPECIAL_DEFENSE: 'SpD', SPEED: 'Spe' }

def pbShowdown
  party = $Trainer.party.compact.map do |pokemon|
    next {
      name: pokemon.species.name.to_s.downcase,
      level: pokemon.level,
      item: pokemon.hasItem? ? pokemon.item.name : nil,
      ball: pokemon.poke_ball,
      moves: pokemon.moves.compact.reject { |move| move.id == 0 }.map { |move| move.name.to_s },
      form: pokemon.form,
      ability: pokemon.ability.name,
      ability_index: pokemon.ability_index,
      nature: pokemon.nature.id,
      ivs: pokemon.iv.select { |_, v| v < 31 }.transform_keys { |k| ESSENTIALS_IV_TO_SHOWDOWN[k] },
      evs: pokemon.ev.select { |_, v| v >= 0 }.transform_keys { |k| ESSENTIALS_IV_TO_SHOWDOWN[k] },
      happiness: pokemon.happiness,
      nickname: pokemon.name.to_s,
      language: pokemon.owner.language,
      timeReceived: pokemon.timeReceived.to_i,
      shiny: pokemon.shiny?,
      gender: pokemon.gender == 0 ? 'M' : 'F'
    }.compact
  end
  filename = @scene.pbEnterText(_INTL("Name for the team?"), 1, 12)
  Dir.mkdir("Saved teams/") if !Dir.exists?("Saved teams/")
	file = File.new("Saved teams/" + filename + ".json", "w+")
	file.write({ teams: [{ pokemon: party }] }.to_json)
end