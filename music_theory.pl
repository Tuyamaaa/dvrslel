:- module(music_theory, [
    note_pc/2,
    enharmonic/2,
    normalize_note/2,
    transpose_note/3,
    parse_chord/4,
    render_chord/4,
    transpose_chord/3,
    major_key_scale/2,
    minor_key_scale/2,
    key_signature_accidentals/2,
    piano_white_black_usage/3,
    diatonic_chords/3,
    chord_tones/2,
    keys_containing_chord/3,
    transpose_progression/3
]).

/** <module> Music theory engine (SWI-Prolog)

Serious foundation for:
- Note normalization (enharmonic)
- Chord parsing/transposition
- Key scales, diatonic chords
- Key signature accidental usage for piano
*/

:- use_module(library(lists)).
:- use_module(library(apply)).

% ------------------------------------------------------------------
% NOTE SYSTEM (12-TET pitch classes)
% ------------------------------------------------------------------

% canonical pitch class names (sharp canonical)
pc_name(0,  'C').
pc_name(1,  'C#').
pc_name(2,  'D').
pc_name(3,  'D#').
pc_name(4,  'E').
pc_name(5,  'F').
pc_name(6,  'F#').
pc_name(7,  'G').
pc_name(8,  'G#').
pc_name(9,  'A').
pc_name(10, 'A#').
pc_name(11, 'B').

% accepted enharmonic spellings -> pitch class
note_pc('C', 0).   note_pc('B#', 0).
note_pc('C#',1).   note_pc('Db', 1).
note_pc('D', 2).
note_pc('D#',3).   note_pc('Eb', 3).
note_pc('E', 4).   note_pc('Fb', 4).
note_pc('F', 5).   note_pc('E#', 5).
note_pc('F#',6).   note_pc('Gb', 6).
note_pc('G', 7).
note_pc('G#',8).   note_pc('Ab', 8).
note_pc('A', 9).
note_pc('A#',10).  note_pc('Bb',10).
note_pc('B', 11).  note_pc('Cb',11).

enharmonic(N1, N2) :-
    note_pc(N1, PC),
    note_pc(N2, PC),
    N1 \= N2.

normalize_note(NoteIn, CanonicalOut) :-
    note_pc(NoteIn, PC),
    pc_name(PC, CanonicalOut).

mod12(N, M) :- M is ((N mod 12) + 12) mod 12.

transpose_note(NoteIn, Semitones, NoteOut) :-
    note_pc(NoteIn, PC0),
    PC1 is PC0 + Semitones,
    mod12(PC1, PCM),
    pc_name(PCM, NoteOut).

% ------------------------------------------------------------------
% CHORD PARSING
% ------------------------------------------------------------------
% parse_chord(+ChordAtom, -RootNoteCanonical, -QualityAtom, -BassOpt)
% Examples:
%   'F#m'    -> Root='F#', Quality='m',  Bass=none
%   'D/F#'   -> Root='D',  Quality='',   Bass='F#'
%   'Bm7/A'  -> Root='B',  Quality='m7', Bass='A'

parse_chord(ChordAtom, RootCanonical, Quality, BassOpt) :-
    atom(ChordAtom),
    atomic_list_concat([Head|Tail], '/', ChordAtom),
    ( Tail = [BassAtom] -> true
    ; Tail = []         -> BassAtom = ''
    ),
    atom_chars(Head, Chars),
    Chars = [L|Rest0],
    char_type(L, alpha),
    ( Rest0 = [Acc|Rest], memberchk(Acc, ['#','b']) ->
        atom_chars(RootRaw, [L,Acc]),
        atom_chars(Quality, Rest)
    ; atom_chars(RootRaw, [L]),
      atom_chars(Quality, Rest0)
    ),
    normalize_note(RootRaw, RootCanonical),
    ( BassAtom == '' -> BassOpt = none
    ; normalize_note(BassAtom, BassOpt)
    ).

render_chord(RootCanonical, Quality, none, ChordAtom) :-
    atom_concat(RootCanonical, Quality, ChordAtom).
render_chord(RootCanonical, Quality, Bass, ChordAtom) :-
    Bass \= none,
    atom_concat(RootCanonical, Quality, Left),
    atomic_list_concat([Left, Bass], '/', ChordAtom).

transpose_chord(ChordIn, Semitones, ChordOut) :-
    parse_chord(ChordIn, Root, Quality, BassOpt),
    transpose_note(Root, Semitones, NewRoot),
    ( BassOpt == none -> NewBass = none
    ; transpose_note(BassOpt, Semitones, NewBass)
    ),
    render_chord(NewRoot, Quality, NewBass, ChordOut).

% ------------------------------------------------------------------
% SCALES + KEY SIGNATURE / PIANO USAGE
% ------------------------------------------------------------------

major_steps([0,2,4,5,7,9,11]).
natural_minor_steps([0,2,3,5,7,8,10]).

scale_from_steps(Tonic, Steps, ScaleNotes) :-
    note_pc(Tonic, TPC),
    maplist(
        {TPC}/[S,N]>>(
            PC is TPC + S,
            mod12(PC, M),
            pc_name(M, N)
        ),
        Steps, ScaleNotes).

major_key_scale(Key, ScaleNotes) :-
    normalize_note(Key, K),
    major_steps(Steps),
    scale_from_steps(K, Steps, ScaleNotes).

minor_key_scale(Key, ScaleNotes) :-
    normalize_note(Key, K),
    natural_minor_steps(Steps),
    scale_from_steps(K, Steps, ScaleNotes).

% Accidentals relative to white set C D E F G A B
white_note('C'). white_note('D'). white_note('E').
white_note('F'). white_note('G'). white_note('A'). white_note('B').

is_black(Note) :-
    sub_atom(Note, _, _, _, '#').

% key_signature_accidentals(+Key, -AccidentalNotes)
% Returns scale notes that are accidentals (# in canonical output).
% Example: D major -> ['F#','C#']
key_signature_accidentals(Key, AccidentalsSorted) :-
    major_key_scale(Key, Scale),
    include(is_black, Scale, Accidentals),
    sort(Accidentals, AccidentalsSorted).

% piano_white_black_usage(+Key, -WhiteUsed, -BlackUsed)
% Which piano key names appear in that major scale.
piano_white_black_usage(Key, WhiteUsed, BlackUsed) :-
    major_key_scale(Key, Scale),
    include(white_note, Scale, W0),
    include(is_black, Scale, B0),
    sort(W0, WhiteUsed),
    sort(B0, BlackUsed).

% ------------------------------------------------------------------
% DIATONIC CHORDS / CHORD TONES / KEY MEMBERSHIP
% ------------------------------------------------------------------

% triad quality by scale degree (major / natural minor)
major_degree_quality(1, '').
major_degree_quality(2, 'm').
major_degree_quality(3, 'm').
major_degree_quality(4, '').
major_degree_quality(5, '').
major_degree_quality(6, 'm').
major_degree_quality(7, 'dim').

minor_degree_quality(1, 'm').
minor_degree_quality(2, 'dim').
minor_degree_quality(3, '').
minor_degree_quality(4, 'm').
minor_degree_quality(5, 'm').
minor_degree_quality(6, '').
minor_degree_quality(7, '').

diatonic_chords(major, Key, Chords) :-
    major_key_scale(Key, Scale),
    findall(Chord,
        (nth1(Deg, Scale, Root),
         major_degree_quality(Deg, Q),
         atom_concat(Root, Q, Chord)),
        Chords).

diatonic_chords(minor, Key, Chords) :-
    minor_key_scale(Key, Scale),
    findall(Chord,
        (nth1(Deg, Scale, Root),
         minor_degree_quality(Deg, Q),
         atom_concat(Root, Q, Chord)),
        Chords).

chord_intervals('',    [0,4,7]).
chord_intervals('m',   [0,3,7]).
chord_intervals('dim', [0,3,6]).
chord_intervals('aug', [0,4,8]).
chord_intervals('7',   [0,4,7,10]).
chord_intervals('m7',  [0,3,7,10]).
chord_intervals('maj7',[0,4,7,11]).

chord_tones(ChordAtom, ToneNames) :-
    parse_chord(ChordAtom, Root, Quality, _Bass),
    note_pc(Root, RPC),
    ( chord_intervals(Quality, Ints) -> true ; Ints = [0,4,7] ),
    maplist(
        {RPC}/[I,N]>>(
            PC is RPC + I, mod12(PC, M), pc_name(M, N)
        ),
        Ints, ToneNames).

% keys_containing_chord(+Mode, +Chord, -Keys)
% Mode = major | minor
keys_containing_chord(Mode, Chord, Keys) :-
    findall(Key,
        ( pc_name(_, Key),           % safe generator with bound first arg from facts
          diatonic_chords(Mode, Key, Chs),
          memberchk(Chord, Chs)
        ),
        K0),
    sort(K0, Keys).

% ------------------------------------------------------------------
% PROGRESSION TRANSPOSE
% Progression = list(list(atom))  e.g. [[ 'Bm' ], [ 'D','A' ], ...]
% ------------------------------------------------------------------

transpose_progression(ProgressionIn, Semitones, ProgressionOut) :-
    maplist(
        maplist({Semitones}/[C,TC]>>transpose_chord(C, Semitones, TC)),
        ProgressionIn,
        ProgressionOut
    ).
% ------------------------------------------------------------------
% ХЭРЭГЛЭГЧИЙН ЦЭС (USER INTERFACE)
% ------------------------------------------------------------------

main_menu :-
    repeat,
    nl,
    writeln('=== Hugjmiin onoliin SYSTEM==='),
    writeln('1. Accord shiljvvleh (Transpose Chord)'),
    writeln('2. Tvlhvvriin gamm harah (Scale)'),
    writeln('3. Diatonik accorduud harah (Diatonic Chords)'),
    writeln('4. Accord ali tvlhvvrt bagtahiig harah (Key Finder)'),
    writeln('5. garah (Exit)'),
    write('songolt (1-5): '),
    read(Choice),
    ( Choice == 5 -> writeln('Bayrtai!'), !
    ; handle_choice(Choice),
      fail
    ).

handle_choice(1) :-
    write('Akkordoo oruul (jishee ni: \'Am7\'(zaawal '' haalttai bic)): '), read(Chord),
    write('Heden hagas ton shiljvvleh we? (toogoor): '), read(Steps),
    transpose_chord(Chord, Steps, Result),
    format('Shiljvvlsen Accord: ~w~n', [Result]).

handle_choice(2) :-
    write('Tvlhvvree oruul (jishee ni: \'D\'): '), read(Key),
    major_key_scale(Key, Major),
    minor_key_scale(Key, Minor),
    format('~w Major scale: ~w~n', [Key, Major]),
    format('~w Minor scale: ~w~n', [Key, Minor]).

handle_choice(3) :-
    write('Tvlhvvree oruul: '), read(Key),
    write('Tuluw (major/minor): '), read(Mode),
    diatonic_chords(Mode, Key, Chords),
    format('~w ~w-ын Diatonik accorduud: ~w~n', [Key, Mode, Chords]).

handle_choice(4) :-
    write('accordoo oruul (jishee ni: \'G\'(zaawal '' haalttai bic)): '), read(Chord),
    keys_containing_chord(major, Chord, MajKeys),
    keys_containing_chord(minor, Chord, MinKeys),
    format('~w bagtsan Major tvlhvvrvvd: ~w~n', [Chord, MajKeys]),
    format('~w bagtsan Minor tvlhvvrvvd: ~w~n', [Chord, MinKeys]).
