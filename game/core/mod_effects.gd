class_name ModEffects
extends RefCounted
## Funciones puras para scripts de mods (ver ModScript) y para el motor de duelo.

static func s32(v: int) -> int:
	v &= 0xffffffff
	return v - 0x100000000 if v >= 0x80000000 else v


## Tres tributos [[duenio, zona], ...] -> posiciones empaquetadas para FUN_0057cd30 (invocacion
## desde la mano tras tres tributos, la misma ruta que Gate Guardian). Es el valor que el estado
## 0x1f de FUN_0056e6e0 calcula a partir del descriptor.
static func pack_tributes(picks: Array) -> int:
	assert(picks.size() == 3)
	var o1: int = picks[0][0] & 1
	var z1: int = picks[0][1] & 7
	var o2: int = picks[1][0] & 1
	var z2: int = picks[1][1] & 7
	var o3: int = picks[2][0] & 1
	var z3: int = picks[2][1] & 7
	return ((8 + o1) * 16 + z1) | (((8 + o2) * 16 + z2) << 8) | (z3 << 16) | (o3 << 20) | 0x800000
