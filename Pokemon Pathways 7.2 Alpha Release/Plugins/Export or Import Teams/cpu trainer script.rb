#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#
#
#  Showdown JSON Importer for Pokémon Essentials CPU Opponents by AceOfSpadesProduc100, built from Trainer.to_trainer from Pokémon Essentials v19.1
#
#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#
$:.push File.join(Dir.pwd, "Ruby Library 3.0.0")
require 'json'
def importopponent
	filename = @scene.pbEnterText(_INTL("Name for the opponent team?"),1,12)
	begin
        file = File.read("Saved teams/" + filename + ".json")
		data_hash = JSON.parse(file)
        # Create trainer object
        tr_name = "CPU Player"
        trainer = NPCTrainer.new(tr_name, :CPUPLAYER)
        trainer.id        = $Trainer.make_foreign_ID
        trainer.items     = nil
        trainer.lose_text = ""
        data_hash['teams'][0]['pokemon'].each do |pkmn_data|
            species = GameData::Species.get(pkmn_data['name'].upcase.gsub(/\W/,'')).species
            pkmn = Pokemon.new(species, pkmn_data['level'] ? pkmn_data['level'] : 50, trainer, false)
            plevel = pkmn_data['level'] ? pkmn_data['level'] : 50
            trainer.party.push(pkmn)
            # Set Pokémon's properties if defined
            if pkmn_data['form']
                pkmn.forced_form = pkmn_data['form'] if MultipleForms.hasFunction?(species, "getForm")
                pkmn.form_simple = pkmn_data['form']
            end
            pkmn.item = pkmn_data['item'].upcase.gsub(/\W/,'').to_sym if pkmn_data['item']
            if pkmn_data['moves'] && pkmn_data['moves'].length > 0
                pkmn_data['moves'].each { |move| pkmn.learn_move(move.upcase.gsub(/\W/,'').to_sym) }
            else
                pkmn.reset_moves
            end
            pkmn.ability_index = pkmn_data['ability_index'] if pkmn_data['ability_index']
            pkmn.ability = pkmn_data['ability'] if pkmn_data['ability']
            if pkmn_data['gender'] == "M"
                pkmn.gender = 0
            else
                pkmn.gender = 1
            end
            pkmn.shiny = (pkmn_data['shiny']) ? true : false
            if pkmn_data['nature']
                pkmn.nature = pkmn_data['nature']
            else
                nature = pkmn.species_data.id_number + GameData::TrainerType.get(trainer.trainer_type).id_number
                pkmn.nature = nature % (GameData::Nature::DATA.length / 2)
            end
                if pkmn_data['ivs']
                    pkmn.iv[:HP] = pkmn_data['ivs']['HP'] ? pkmn_data['ivs']['HP'] : pkmn.iv[:HP] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
                    pkmn.iv[:ATTACK] = pkmn_data['ivs']['Atk'] ? pkmn_data['ivs']['Atk'] : pkmn.iv[:ATTACK] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
                    pkmn.iv[:DEFENSE] = pkmn_data['ivs']['Def'] ? pkmn_data['ivs']['Def'] : pkmn.iv[:DEFENSE] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
                    pkmn.iv[:SPECIAL_ATTACK] = pkmn_data['ivs']['SpA'] ? pkmn_data['ivs']['SpA'] : pkmn.iv[:SPECIAL_ATTACK] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
                    pkmn.iv[:SPECIAL_DEFENSE] = pkmn_data['ivs']['SpD'] ? pkmn_data['ivs']['SpD'] : pkmn.iv[:SPECIAL_DEFENSE] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
                    pkmn.iv[:SPEED] = pkmn_data['ivs']['Spe'] ? pkmn_data['ivs']['Spe'] : pkmn.iv[:SPEED] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
                else
                    pkmn.iv[:HP] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
                    pkmn.iv[:ATTACK] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
                    pkmn.iv[:DEFENSE] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
                    pkmn.iv[:SPECIAL_ATTACK] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
                    pkmn.iv[:SPECIAL_DEFENSE] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
                    pkmn.iv[:SPEED] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
                end
                if pkmn_data['evs']
                    pkmn.ev[:HP] = pkmn_data['evs']['HP'] ? pkmn_data['evs']['HP'] : pkmn.ev[:HP] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
                    pkmn.ev[:ATTACK] = pkmn_data['evs']['Atk'] ? pkmn_data['evs']['Atk'] : pkmn.ev[:ATTACK] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
                    pkmn.ev[:DEFENSE] = pkmn_data['evs']['Def'] ? pkmn_data['evs']['Def'] : pkmn.ev[:DEFENSE] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
                    pkmn.ev[:SPECIAL_ATTACK] = pkmn_data['evs']['SpA'] ? pkmn_data['evs']['SpA'] : pkmn.ev[:SPECIAL_ATTACK] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
                    pkmn.ev[:SPECIAL_DEFENSE] = pkmn_data['evs']['SpD'] ? pkmn_data['evs']['SpD'] : pkmn.ev[:SPECIAL_DEFENSE] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
                    pkmn.ev[:SPEED] = pkmn_data['evs']['Spe'] ? pkmn_data['evs']['Spe'] : pkmn.ev[:SPEED] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
                else
                    pkmn.ev[:HP] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
                    pkmn.ev[:ATTACK] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
                    pkmn.ev[:DEFENSE] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
                    pkmn.ev[:SPECIAL_ATTACK] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
                    pkmn.ev[:SPECIAL_DEFENSE] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
                    pkmn.ev[:SPEED] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
                end
            pkmn.happiness = pkmn_data['happiness'] if pkmn_data['happiness']
            pkmn.name = pkmn_data['nickname'] if pkmn_data['nickname'] && !pkmn_data['nickname'].empty?
            pkmn.poke_ball = pkmn_data['ball'] if pkmn_data['ball']
            pkmn.calc_stats
        end
        return trainer
    rescue
		pbMessage(_INTL("An error occurred. Check for JSON-specific errors in a JSON validator, or refer to \"showdowntoessentialsguide.txt\" for team-specific errors."))
	end
end
def pbCPUTrainerBattle(doubleBattle=false, canLose=false, outcomeVar=1)
    begin
        setBattleRule("outcomeVar",outcomeVar) if outcomeVar!=1
        setBattleRule("canLose") if canLose
        setBattleRule("double") if doubleBattle
        $PokemonGlobal.nextBattleBGM = pbListScreen("Battle theme", MusicFileLister.new(true,nil))
        ret = pbOrganizedBattleEx(importopponent,nil,
        "",
        "")
        return ret
    rescue
        pbMessage(_INTL("The battle didn't start, because of an error."))
    end
  end