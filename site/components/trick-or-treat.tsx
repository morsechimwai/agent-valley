'use client';

import { useContext } from 'react';
import { announce } from '@/components/announcer';
import { Clock } from '@/components/clock';
import { ScreenContext, type Answer } from '@/components/hero-screen';
import { Icon } from '@/components/icons';
import { Mascot } from '@/components/mascot';

const REPLY: Record<Answer, string> = {
  allow: 'Thanks. Walt already took the peanut butter cups.',
  deny: 'Fair. Trick it is.',
};

// Halloween: the panel's first row is Sunny at the door asking for candy, with the app's two
// answers. Answered, the row goes back to work and its buttons go.
export function TrickOrTreat() {
  const { answered, answer } = useContext(ScreenContext);
  const pick = (a: Answer) => {
    answer(a);
    announce(REPLY[a]);
  };
  return (
    <>
      {/* Its own project's line over it, as the ALL tab draws one; the card then names only the branch. */}
      <p className="p-group hw" aria-hidden="true"><span>haunted-house</span> · 1 session</p>
      <div className="p-card trick hw">
        <span className="draw" aria-hidden="true">
          {answered ? <Mascot who="guru" pose="work" /> : <Mascot who="guru" pose="wave" dot />}
        </span>
        <div>
          <div aria-hidden="true">
            <p className="p-line">
              <b className="t">Trick or treat <Icon id="out" /></b>
              {!answered && <span><em>needs you</em> <span className="p-wait"><Clock from={14} /></span> <span className="model">Sonnet 5.5</span></span>}
            </p>
            <p className="p-dim"><Icon id="branch" /><span>porch</span></p>
            <p>{answered ? REPLY[answered] : '> Bash eat ./candy/*'}</p>
          </div>
          {!answered && (
            <div role="group" aria-label="Trick or treat. Sunny asks to run eat ./candy/*." className="p-answer">
              <button type="button" onClick={() => pick('allow')}><span>Allow once</span></button>
              <button type="button" className="deny" onClick={() => pick('deny')}><span>Deny</span></button>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
