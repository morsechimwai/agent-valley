import { CODE, ComicPage, H2, PRE, comicMetadata } from '../comic-page';

export const metadata = comicMetadata('both-on-main');

export default function BothOnMain() {
  return (
    <ComicPage slug="both-on-main">
      <h2 className={H2}>Two sessions, one folder</h2>
      <p>
        Start two Claude Code sessions in the same folder, and they share one set of files on one branch. Neither knows
        the other is there. An edit from one can break what the other is halfway through, the tests fail for reasons
        neither of them wrote, and a commit from one can carry half of the other&apos;s work. In the comic it&apos;s a
        torn printout. In a repository it&apos;s two tasks tangled on main.
      </p>

      <h2 className={H2}>Give each session its own worktree</h2>
      <p>
        A git worktree is a second checkout of the same repository: its own folder and its own branch, sharing one
        history. Start each session in one, each in its own terminal:
      </p>
      <pre className={PRE} tabIndex={0} aria-label="Two sessions, each in a worktree of its own">
        {`claude --worktree fix-login
claude --worktree dark-mode`}
      </pre>
      <p className="mt-4">
        Claude Code makes each folder under <code className={CODE}>.claude/worktrees/</code>, on a new branch from your
        repository&apos;s default branch: <code className={CODE}>worktree-fix-login</code> and{' '}
        <code className={CODE}>worktree-dark-mode</code>. Add <code className={CODE}>.claude/worktrees/</code> to your{' '}
        <code className={CODE}>.gitignore</code>. A worktree is a fresh checkout, so files git ignores, like{' '}
        <code className={CODE}>.env</code>, aren&apos;t in it. Name them in a{' '}
        <code className={CODE}>.worktreeinclude</code> file at the root, and Claude Code copies them in.
      </p>
      <p className="mt-4">
        When you leave a session that has work in its worktree, Claude Code asks whether to keep the worktree or remove
        it. Keep it, and merge the branch the way you would merge anyone&apos;s.
      </p>

      <h2 className={H2}>See which is which</h2>
      <p>
        <code className={CODE}>git worktree list</code> prints every worktree with its folder and branch. It tells you
        where each session is, not what it&apos;s doing.
      </p>
      <p className="mt-4">
        <a href="/">AgentValley</a> shows every Claude Code session as a card in the notch&apos;s panel: the
        project&apos;s name, its branch, a small mark when the session runs in a worktree of its own, and the step
        it&apos;s on, like Edit LoginView.swift. Two cards in one project, both on main, both in the same file: that is
        the sign. AgentValley doesn&apos;t warn you about it. It shows it, from ten o&apos;clock on, and someone has to
        look.
      </p>
    </ComicPage>
  );
}
