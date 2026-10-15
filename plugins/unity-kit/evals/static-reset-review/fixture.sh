#!/usr/bin/env bash
set -e
mkdir -p ProjectSettings Packages Assets/Scripts
printf "m_EditorVersion: 6000.0.84f1\n" > ProjectSettings/ProjectVersion.txt
printf "%%YAML 1.1\n--- !u!159 &1\nEditorSettings:\n  m_EnterPlayModeOptionsEnabled: 1\n  m_EnterPlayModeOptions: 1\n" > ProjectSettings/EditorSettings.asset
printf "{\n  \"dependencies\": {\n    \"com.unity.render-pipelines.universal\": \"17.0.4\"\n  }\n}\n" > Packages/manifest.json
printf "fileFormatVersion: 2\nguid: 94c660952f2479d4c83dab160d3dc673\nfolderAsset: yes\n" > Assets/Scripts.meta
printf "using UnityEngine;\n\npublic class Player : MonoBehaviour\n{\n    void Update() { }\n}\n" > Assets/Scripts/Player.cs
printf "fileFormatVersion: 2\nguid: 5f1c2a7e9b3d4c8a8e6f0a1b2c3d4e5f\nMonoImporter:\n  serializedVersion: 2\n" > Assets/Scripts/Player.cs.meta
printf "using UnityEngine;\n\npublic class Health : MonoBehaviour\n{\n    public static int AliveCount;\n    void OnEnable() { AliveCount++; }\n    void OnDisable() { AliveCount--; }\n}\n" > Assets/Scripts/Health.cs
printf "fileFormatVersion: 2\nguid: 7a2b3c4d5e6f708192a3b4c5d6e7f809\nMonoImporter:\n  serializedVersion: 2\n" > Assets/Scripts/Health.cs.meta
