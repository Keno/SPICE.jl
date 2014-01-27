module SPICE

include("../deps/deps.jl")

using SIUnits
using DataFrames
using DataArrays

export read_ascii_table

# read_ascii_table(filename, colnames)
#
# Reads SPICE data written to an ASCII file using the spice command
# `set file-type=ascii`. Unfortunately this data format does not include
# metadata but just the raw data dump, so you'll have to manually specify
# the column names. This function will also apply units based on the 
# first character of the specified column names Volts for "V", Amperes for
# "I" and Seconds for "t". In `ngspice` this format is produced by the
# `wrdata` command
#

function read_ascii_table(f,cnames; sweepcol = "in")
    a=Array(Float64,0)
    c=0
    open(f) do fh
        for l in EachLine(fh)
            if c== 0
                c=length(split(l,' ',-1,false))-1
            end
            for x in split(l,' ',-1,false)
                x=="\n" && continue
                push!(a,parsefloat(x))
            end
        end
    end
    a = reshape(a,(c,itrunc(length(a)/c)))'
    d = DataFrame(a)
    issweep = true
    to_delete = ASCIIString[]
    for col in Base.names(d)
        if issweep
            push!(to_delete,col)
            issweep = false
        else
            #Keep this column, next one is sweep
            issweep = true
        end
    end
    sweep = d["x1"]
    delete!(d,to_delete)
    rename!(d,Base.names(d),[cnames])
    d[sweepcol] = sweep
    d = unitify(d,[c[1] == 'I' ? Ampere : c[1] == 't' ? Second  : Volt for c in Base.names(d)]);
end

function unitify(d,units)
    names = Base.names(d)
    ret = DataFrame()
    for i = 1:length(names)
        ret[names[i]] = d[names[i]]*units[i]
    end
    ret
end

function beginswith_ci(line,query)
    if endof(query) > endof(line)
        return false
    end
    lowercase(line[1:(prevind(line,endof(query)+1))]) == query
end

immutable TokIterator
    s::String
    offset::Int
end

import Base: start, next, done

start(t::TokIterator) = t.offset
function next(t::TokIterator,pos)
    e = endof(t.s)
    paren = 0
    orgpos = pos
    while done(t.s,pos)
        lastpos = pos
        c, pos = next(t.s,pos)
        if c == '('
            paren += 1
        elseif c == ')'
            paren -= 1
        elseif c == ',' && paren < 1
            return t.s[orgpos:lastpos], pos
        elseif isspace(c)
            if orgpos == lastpos #leading whitespace
                orgpos = pos
            else
                return t.s[orgpos:lastpos], skipwspace(s,lastpos)
            end
        end
    end
    t.s[orgpos:pos], pos
end
done(t::TokIterator,pos) = done(t.s,pos)

function skipwspace(s,offset)
    while !done(s,offset)
        c, n = next(s,offset)
        if !isspace(c)
            break
        end
        offset = n
    end
    offset
end

function getnum(s,pos)
    orgpos = pos
    while !done(s,pos)
        c, n = next(s,pos)
        if !isdigit(c)
            break
        end
        pos = n
    end
    offset, parseint(s[orgpos:pos])
end

function atodims(s,offset)
    offset = skipwspace(s,offset)
    c, offset = next(s,offset)
    needbracket = false
    state = 0
    sep = '\0'
    data = Array(Uint,0)
    if c == '['
        offset = skipwspace(s,offset)
        needbracket = true
    end
    while state != 3
        if state == 0
            if !isdigit(c)
                push!(data,0)
            else
                offset, d = getnum(s,offset)
                push!(data,d)
            end
            state = 1
        elseif state == 1 # p after a number, looking for ',' or ']'
            if sep == '\0'
                sep = c

            if c == ']' && c == sep
                state = 2
            elseif c == ',' && c == sep
                state = 0
            end 
            # skip other characters, this is the behavior of SPICE 3. I believe it 
            # to be a bug in the original implementation that went unnoticed because
            # this is an error case. Either way, I will not change it for compatibility
            # reasons
        elseif state == 2 #after a ']', either at the end or looking for '['
            if c == '['
                state = 0
            else
                state = 3
            end
        end
        offset = skipwspace(s,offset)
        if done(s,offset)
            break
        end
    end
    if state == 3
        err = !needbracket
    else 
        err = needbracket
    end
    if err 
        error("Incomplete input!")
    end
    data
end

immutable Variable{T}
    name
    length
    data::Array{T}
end

using SIUnits

function vtype_to_unit(vtype)
    if vtype == "voltage"
        return Volts
    elseif vtype == "current"
        return Ampere
    end
end

function read_raw(io::IO)
    title = "default title"
    date = "unknown date"
    plotname = "unnamed plot"
    flags = 0
    raw_padded = true
    nvars = 0
    npoints = 0
    dimensions = (0,)
    variables = Array(Variable,0)
    while !eof(io)
        line = readline(io)
        if beginswith_ci(line,"title:")
            title = strip(line[7:end])
        elseif beginswith_ci(line,"date:")
            date = strip(line[6:end])
        elseif beginswith_ci(line,"plotname:")
            plotname = strip(line[10:end])
        elseif beginswith_ci(line,"flags:")
            for tok in TokIterator(line,7)
                if lowercase(tok) == "real"
                    flags |= VF_REAL
                elseif lowercase(tok) == "complex"
                    flags |= VF_COMPLEX
                elseif lowercase(tok) == "unpadded"
                    raw_padded = false
                elseif lowercase(tok) == "padded"
                    raw_padded = true
                else
                    error("Unknown flag $tok")
                end
            end
        elseif beginswith_ci(line,"no. variables:")
            nvars = parseint(strip(line[14:end]))
        elseif beginswith_ci(line,"no. points:")
            npoints = parseint(strip(line[11:end]))
        elseif beginswith_ci(line,"dimensions:")
            npoints == 0 && error("Mispaced Dimensions: line")
            dimensions = tuple(atodims(line[11:end])...)
            prod(dimensions) != npoints && error("dimension mismatch")
        elseif beginswith_ci(line,"command:")
            error("Unimplemented")
        elseif beginswith_ci(line,"option:")
            error("Unimplemented")
        elseif beginswith_ci(line,"variables:")
            for i = 1:nvars
                # Here we assume one line per variable. I don't know if that's always the case. If not, 
                # This needs to be changed
                s = readline(io)
                it = TokIterator(line,0)
                state = start(it)
                _, state = next(it,state)
                name, state = next(it,state)
                vartype, state = next(it,state)

                if isdigit(name)
                    error("Unimplemented")
                end

                while !done(s,state)
                    tok, state
                    if beginswith_ci(tok,"min=")
                        vflags |= VF_MINGIVEN
                        parseint(tok[4:end])
                    elseif beginswith_ci(tok,"max=")
                        vflags |= VF_MAXGIVEN
                        parseint(tok[4:end])
                    elseif beginswith_ci(tok,"color=")
                        vcolor = tok[6:end]
                    elseif beginswith_ci(tok,"scale=")
                        v_scale = tok[6:end]
                    elseif beginswith_ci(tok,"grid=")
                        vgrid = tok[5:end]
                    elseif beginswith_ci(tok,"plot=")
                        vplot = tok[5:end]
                    elseif beginswith_ci(tok,"dims=")

                    else
                        error("Bad parameter")
                    end
                end
                push!(variables,Variable(name,npoints,Array(quantity(flags & VF_REAL > 0 ? Float64 : Complex128,vtype_to_unit(v_type)),0)))
            end
        elseif beginswith_ci(line,"binary:") || beginswith_ci("values:")
            c = read(io,Uint8)
            is_ascii = c == uint8('v') || c == uint8('V')

            for i=1:npoints
                if is_ascii
                    error("Unimplemented")
                else
                    for v in variables
                        if i <= v.length
                            v.data[i] = read(io,eltype(v.data))
                        elseif raw_padded
                            read(io,eltype(v.data))
                        end
                    end
                end
            end
            break
        else
            error("Malformed file")
        end
    end
end

end # module
