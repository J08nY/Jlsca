# Play around with this for multi-processing.
# addprocs(2)

using Distributed
using Jlsca.Sca
using Jlsca.Trs
using Jlsca.Align
@everywhere using Jlsca.Sca
@everywhere using Jlsca.Trs
@everywhere using Jlsca.Align

# our vanilla  main function
function gofaster()
  if length(ARGS) < 1
    print("no input trace\n")
    return
  end

  filename = ARGS[1]
  direction::Direction = (length(ARGS) > 1 && ARGS[2] == "BACKWARD" ? BACKWARD : FORWARD)
  params = getParameters(filename, direction)
  if params == nothing
    throw(ErrorException("Params cannot be derived from filename, assign and config your own here!"))
    # params = DpaAttack(AesSboxAttack(),MIA())
  end

  params.analysis = MIA()

  @everywhere begin
      trs = InspectorTrace($filename)

      setPostProcessor(trs, CondAvg(SplitByTracesBlock()))
  end

  numberOfTraces = length(trs)

  ret = sca(DistributedTrace(), params, 1, numberOfTraces)

  return ret
end

@time gofaster()
