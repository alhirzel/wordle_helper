using LinearAlgebra: norm
using UnicodePlots: barplot

"""
All Wordle words have no special characters and are five letters long.

This dictionary is normalized to lowercase.
"""
wordle_dictionary() = filter(lowercase.(readlines("/usr/share/dict/words"))) do word
	isnothing(match(r"^[a-z]{5}$", word)) && return false
	# certain manual exclusions apply...
	word in ["milan"] && return false
	return true
end

"""
Return distribution of letters in word list.
"""
function letter_occurrences(words::Vector{String})
	o = fill(0, (26,))
	for w in words, i in 1:5
		letter = w[i]
		o[letter - 'a' + 1] += 1
	end
	return o
end

"""
Model of the knowledge at each step of the game.
"""
mutable struct Knowledge
	"number of attempts so far"
	nattempts::Integer
	"list of letters that are not present"
	not_present::Vector{Char}
	"letters that are known to be present in the word but only excluded from certain positions (false in a position means not present)"
	present::Dict{Char,NTuple{5,Bool}}
	"for each position, its letter"
	placed::Vector{Union{Nothing,Char}}

	Knowledge() = new(0, [], Dict(), [nothing, nothing, nothing, nothing, nothing])
end

"""
Return function that produces higher values for a `word` that could reveal new information in the context of a remaining valid set of `words` and existing `knowledge`.

One objective is to find letters that are `placed` or `present`.
By trying letters that are present with high frequency in the dictionary words, there is a chance that they will be `placed` by chance, or proved `present`.

TODO - what are cases that it makes sense to incorporate `not_present`?
TODO - special case when we know what all the letters are (i.e. two placed, three present)
"""
function information_gained_heuristic(words, knowledge)
	os = letter_occurrences(words)
	normfreq = os ./ maximum(os) # normalized frequency of each letter a-z
	return word -> begin
		letters = Vector{Char}(word) .- 'a' .+ 1
		# note: only use each letter once when considering its frequency value, so that more presence information is gained
		return norm([normfreq[l] for l in unique(letters)])
	end
end

"""
Filter `words` in-place using `knowledge` gained to this point about the goal word.

Remove words that contain eliminated letters, that do not match placed letters, or that do not contain letters that are known to be present in places they have not been rejected from.
"""
remove_impossible_words!(words, knowledge) = filter!(words) do word
	letters = Vector{Char}(word)

	# if one of the letters is blacklisted, reject
	isempty(intersect(knowledge.not_present, letters)) || return false

	# if the word doesn't match known letters, reject
	for (known, letter) in zip(knowledge.placed, letters)
		isnothing(known) && continue
		known == letter || return false
	end

	# if the word doesn't match what is known about present letters, reject
	for (present_letter, in_places) in knowledge.present
		present_letter ∈ word || return false
		for (i, letter) in enumerate(letters)
			if present_letter == letter && in_places[i] == false
				# previously, proved it can't be here already
				return false
			end
		end
	end

	# if all of those tests pass, the word is a possibility
	return true
end

"""
Updates `knowledge` after a `guess` reveals a `response` from Wordle.

The `response` is formatted as a five-character string composed of the letters N, W and C.
The letter N in a position means the guessed word has a letter in that position which is not present in the target word.
Similarly, the letter W means the letter is present but in the wrong spot.
Finally, the letter C means the `guess` contains a correct letter at that position.

TODO clarify the wording above...
"""
function update!(knowledge::Knowledge, guess::String, response::String)
	knowledge.nattempts += 1
	for (i, g, r) in zip(1:5, Vector{Char}(lowercase(guess)), Vector{Char}(uppercase(response)))
		if r == 'N'
			push!(knowledge.not_present, g)
		elseif r == 'W'
			existing_or_new = get(knowledge.present, g, (true, true, true, true, true))
			# flip true -> false in the position we just learned about
			knowledge.present[g] = Tuple(existing_or_new .& (i .!= collect(1:5)))
		elseif r == 'C'
			knowledge.placed[i] = g
			# assume this placement is related to the presence info we already had
			if g in keys(knowledge.present)
				# TODO - how to best handle doubled letters?
				delete!(knowledge.present, g)
			end
		else
			error("invalid response $response (letter $r) for guess $guess")
		end
	end
end

"""
Convenience function to show the current state
"""
function show_state(words, knowledge)
	println("# Iteration $(knowledge.nattempts):")

	os = letter_occurrences(words)
	order = sortperm(os; rev=true)
	display(barplot(collect('a':'z')[order][1:5], os[order][1:5])); println()

	n = min(5, length(words))
	top_words = reshape(words[1:n], (1, n))
	println("top $n word list (out of $(length(words)) total): $(join(top_words, ", ", ", and "))")
	println("")
end

optimize_words!(words, knowledge) = sort!(words, by = information_gained_heuristic(words, knowledge); rev=true)

words = wordle_dictionary()
knowledge = Knowledge()
optimize_words!(words, knowledge)
show_state(words, knowledge) # best starting words...

update!(knowledge, "rhino", "NNWWN")
remove_impossible_words!(words, knowledge)
optimize_words!(words, knowledge)
show_state(words, knowledge)

update!(knowledge, "inset", "WWNNN")
remove_impossible_words!(words, knowledge)
optimize_words!(words, knowledge)
show_state(words, knowledge)

update!(knowledge, "admin", "WNNCW")
remove_impossible_words!(words, knowledge)
optimize_words!(words, knowledge)
show_state(words, knowledge)

update!(knowledge, "panic", "CCCCC")
remove_impossible_words!(words, knowledge)
optimize_words!(words, knowledge)
show_state(words, knowledge)

# won
