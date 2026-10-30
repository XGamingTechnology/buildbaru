"""Static checks that need no FXServer or database: every Lua file compiles
under Lua 5.4 and every shell script parses."""
import shutil
import subprocess
import unittest

from helpers import ROOT


class StaticTests(unittest.TestCase):
    def test_all_lua_files_compile(self):
        from lupa import lua54

        compile_error = lua54.LuaRuntime().eval('function(src, name) local _, err = load(src, name); return err end')
        files = sorted((ROOT / 'fivem').rglob('*.lua'))
        self.assertGreater(len(files), 10)
        for path in files:
            with self.subTest(path.relative_to(ROOT)):
                self.assertIsNone(compile_error(path.read_text(encoding='utf-8'), str(path)))

    @unittest.skipUnless(shutil.which('bash'), 'bash not available')
    def test_shell_scripts_parse(self):
        scripts = sorted((ROOT / 'deploy').rglob('*.sh'))
        self.assertGreater(len(scripts), 0)
        for path in scripts:
            with self.subTest(path.relative_to(ROOT)):
                subprocess.run(['bash', '-n', str(path)], check=True)

    def test_selftest_is_not_enabled_by_the_production_example(self):
        example = (ROOT / 'fivem' / 'server.cfg.example').read_text(encoding='utf-8')
        self.assertNotIn('sentinel_selftest', example)


if __name__ == '__main__':
    unittest.main()
