"""AtoMizer beside the stock effects: DELAY, SPRING REV, PLATE REV and DARK REV give up their words."""
from remix.schema import Proof, Remix
REMIX = Remix(family="effects", proof=Proof.RENDER,
              proof_note="its render gates (verify_atomizer: dsp_host, bit-exact against atomizer_ref.py), "
                         "20 Oct 2026; not on hardware",
              name="atomizer",
              doc="AtoMizer beside the stock effects (all but DELAY, SPRING REV, PLATE REV and DARK REV, "
                  "whose words and id it takes).",
              modules=("ATOMIZER",
                       "FILTER", "EQUALIZER", "DJ EQ", "PHASER", "FLANGER",
                       "CHORUS", "SPATIALIZER", "COMB FILTER", "COMPRESSOR", "LO-FI"),
              fallback="NONE")
