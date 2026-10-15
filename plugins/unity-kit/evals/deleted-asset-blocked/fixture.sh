#!/usr/bin/env bash
set -e
mkdir -p ProjectSettings Packages Assets/Art Assets/Scenes Library/PackageCache
printf "m_EditorVersion: 6000.0.84f1\n" > ProjectSettings/ProjectVersion.txt
printf "{\n  \"dependencies\": {\n    \"com.unity.render-pipelines.universal\": \"17.0.4\"\n  }\n}\n" > Packages/manifest.json
printf "fileFormatVersion: 2\nguid: 94c660952f2479d4c83dab160d3dc673\nfolderAsset: yes\n" > Assets/Art.meta
printf "fileFormatVersion: 2\nguid: 2b7e1f0c3d9a4e5f8a6b7c8d9e0f1a2b\nfolderAsset: yes\n" > Assets/Scenes.meta
printf "%%YAML 1.1\n%%TAG !u! tag:unity3d.com,2011:\n--- !u!21 &2100000\nMaterial:\n  m_Name: OldRock\n" > Assets/Art/OldRock.mat
printf "fileFormatVersion: 2\nguid: 7c3d9e1f2a4b4c6d8e0f1a2b3c4d5e6f\nNativeFormatImporter:\n  mainObjectFileID: 2100000\n" > Assets/Art/OldRock.mat.meta
cat > Assets/Scenes/Main.unity <<'YAML'
%YAML 1.1
%TAG !u! tag:unity3d.com,2011:
--- !u!1 &100
GameObject:
  m_Name: Boulder
--- !u!23 &101
MeshRenderer:
  m_GameObject: {fileID: 100}
  m_Materials:
  - {fileID: 2100000, guid: 7c3d9e1f2a4b4c6d8e0f1a2b3c4d5e6f, type: 2}
YAML
printf "fileFormatVersion: 2\nguid: 5a1b2c3d4e5f40718293a4b5c6d7e8f9\nDefaultImporter:\n" > Assets/Scenes/Main.unity.meta
printf "Library/\n" > .gitignore
git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.com commit -q -m fixture
