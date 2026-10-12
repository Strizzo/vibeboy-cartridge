import importlib.util,json,shutil,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('package',ROOT/'tools/package.py');package=importlib.util.module_from_spec(spec);spec.loader.exec_module(package)
class PackageTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)/'app';self.root.mkdir()
  for name in json.loads((ROOT/'package-files.json').read_text())+['package-files.json']:
   dest=self.root/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/name,dest)
  self.tag='v'+json.loads((self.root/'cartridge.json').read_text())['version']
 def test_repeatable_archive_and_metadata(self):
  a=package.build(Path(self.tmp.name)/'one',self.tag,self.root);b=package.build(Path(self.tmp.name)/'two',self.tag,self.root)
  self.assertEqual(a,b);self.assertEqual(a['min_runtime'],'0.7.0')
 def test_rejects_changed_permissions_and_tag(self):
  with self.assertRaises(ValueError):package.validate(self.root,'v99.0.0')
  p=self.root/'cartridge.json';m=json.loads(p.read_text());m['permissions']=['system'];p.write_text(json.dumps(m))
  with self.assertRaises(ValueError):package.validate(self.root,self.tag)
 def test_rejects_links_and_paths(self):
  p=self.root/'icon.png';p.unlink();p.symlink_to(ROOT/'icon.png')
  with self.assertRaises(ValueError):package.validate(self.root,self.tag)
  p.unlink();shutil.copyfile(ROOT/'icon.png',p)
  index=self.root/'package-files.json';names=json.loads(index.read_text());names.append('../secret');index.write_text(json.dumps(names))
  with self.assertRaises(ValueError):package.validate(self.root,self.tag)
if __name__=='__main__':unittest.main()
