# This file is part of Jlsca, license is GPLv3, see https://www.gnu.org/licenses/gpl-3.0.en.html
#
# Author: Cees-Bart Breunesse

export SampleCombination
abstract type SampleCombination end

export AbsDiff
"""
Combines samples a and b as abs(a - b).
"""
mutable struct AbsDiff <: SampleCombination end

combine(c::AbsDiff, a::T, b::T) where {T} = abs(Float64(a) - b)
allocate(c::AbsDiff, xl::Int) = Vector{Float64}(undef,xl)

export Xor
"""
Combines samples a and b as xor(a,b). Can only be used on traces with bits.
"""
mutable struct Xor <: SampleCombination end

combine(c::Xor, a::Bool, b::Bool) = Bool(a ⊻ b)
allocate(c::Xor, xl::Int) = BitVector(undef,xl)

export SecondOrderPass
"""
An efficient second order sample combinator. 

This pass computes the second order triangle (i.e. every sample combined with every other sample), efficiently, per column. It is important that you add this pass *last*.

The `sca` function will attack per column if too many samples are offered (see the `maxCols` parameter in `DpaAttack`). Normally this would mean that all samples but the column under attack are discarded which is is a huge waste. This second order pass will only compute the samples needed for the column under attack, significantly speeding up the attack and requiring much less memory. 

The constructor takes an optional single argument of type `SampleCombination`. The default is `AbsDiff`. The alternative is `Xor()`, if the input is a BitVector, for whiteboxes.

# Example
```
trs = InspectorTrace("bla.trs")

attack = AesSboxAttack()
analysis = CPA()
params = DpaAttack(attack,analysis)
params.maxCols = 100000

addSamplePass(trs, SecondOrderPass(AbsDiff()))

setPostProcessor(trs, CondAvg())
sca(trs,params)
``` 
"""
mutable struct SecondOrderPass <: Pass
    cmb::SampleCombination 
    li::Int
    ui::Int
    lj::Int
    uj::Int
    cols::UnitRange

    SecondOrderPass() = new(AbsDiff())
    SecondOrderPass(cmb::SampleCombination) = new(cmb)
end

outtype(a::SecondOrderPass, ::AbstractVector) = Vector{Float64}()
outlength(a::SecondOrderPass, xl::Int, ::AbstractVector) = div(xl * (xl -1), 2)

function offset2samples(o,xl)
    c = 1
    for i in 1:xl
        for j in i+1:xl
            if c == o
                return (i,j)
            end
            c += 1
        end
    end
end

function loop1(cmb::SampleCombination,c::Int,i::Int,lj::Int,xl::Int,y::AbstractVector,x::AbstractArray{T,1}) where {T}
    for j in lj:xl
        y[c] = combine(cmb, x[i], x[j])
        c += 1
    end
    return c
end

function loop2(cmb::SampleCombination,c::Int,li::Int,ui::Int,xl::Int,y::AbstractVector,x::AbstractArray{T,1}) where {T}
    for i in li+1:(ui-1)
        for j in i+1:xl
            y[c] = combine(cmb, x[i], x[j])
            c += 1
        end
    end
    return c        
end

function loop3(cmb::SampleCombination,c::Int,i::Int,uj::Int,y::AbstractVector,x::AbstractArray{T,1}) where {T}
    for j in i+1:uj
        y[c] = combine(cmb, x[i], x[j])
        c += 1
    end
    return c
end

function pass(a::SecondOrderPass, x::AbstractVector, idx::Int)
    xl = length(x)
    return pass(a,x,idx,1:div(xl * (xl-1),2))
end

function pass(a::SecondOrderPass, x::AbstractVector, idx::Int, cols::UnitRange)
    xl = length(x)
    if !(isdefined(a,:cols) && cols == a.cols)
        (li,lj) = offset2samples(cols[1],xl)
        (ui,uj) = offset2samples(cols[end],xl)
        a.li = li
        a.ui = ui
        a.lj = lj
        a.uj = uj
        a.cols = cols 
    else
        li = a.li
        ui = a.ui
        lj = a.lj
        uj = a.uj
        cols = a.cols
    end
    # @show (li,ui,lj,uj)

    yl = length(cols)
    y = allocate(a.cmb, yl)
    c = 1

    i = li
    c = loop1(a.cmb,c,i,lj,min(yl-c+1,xl-lj+1)+lj-1,y,x)
    c = loop2(a.cmb,c,li,ui,xl,y,x)
    i = ui
    c = loop3(a.cmb,c,i,min(yl-c+1,uj-i)+i,y,x)

    # @assert c == yl + 1
    return y
end        
