# SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
# SPDX-License-Identifier: GPL-3.0-only
{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      self',
      ...
    }:
    let
      inherit (pkgs.qt6) qtbase qtdeclarative;
      apps = [
        "announcer"
        "bullpen"
        "dugout"
        "gate"
        "jumbotron"
        "lineup"
        "outfield"
        "tarp"
      ];
      # Where qmllint finds the types of everything the apps import: Qt's own
      # modules, Quickshell's and qml-niri's (both install .qmltypes), and the
      # app's installed tree, which has the generated theme file, for
      # `import modules.*`.
      importPaths = [
        "${qtdeclarative}/${qtbase.qtQmlPrefix}"
        "${inputs.quickshell.packages.${system}.default}/${qtbase.qtQmlPrefix}"
        "${inputs.qml-niri.packages.${system}.default}/${qtbase.qtQmlPrefix}"
      ];
      # Fail on any warning except two categories:
      # - unqualified: reading an outer id from a delegate. The apps do this
      #   over a hundred times; qualifying them all needs `pragma
      #   ComponentBehavior: Bound` and required properties throughout.
      # - uncreatable-type: Quickshell describes PanelWindow and friends as
      #   uncreatable, though they are what every app is built from.
      # A false positive elsewhere gets a `// qmllint disable <category>`
      # comment where it happens, with the reason.
      flags = [
        "--max-warnings"
        "0"
        "--unqualified"
        "disable"
        "--uncreatable-type"
        "disable"
      ];
      # qmllint's plain output can leave warnings out, so it writes JSON and
      # jq prints every warning as file:line:column.
      lint =
        name: files:
        let
          root = "${self'.packages.${name}}/share/birdland";
        in
        ''
          echo "qmllint: ${name}"
          qmllint ${lib.escapeShellArgs flags} --json "$TMPDIR/${name}.json" \
            ${lib.concatMapStringsSep " " (p: "-I ${p}") (importPaths ++ [ root ])} \
            ${lib.concatMapStringsSep " " (f: "${root}/${f}") files} || failed=1
          jq -r --arg root "${root}/" \
            '.files[] | (.filename | ltrimstr($root)) as $file | .warnings[]
              | "\(.type): \($file):\(.line):\(.column): \(.message) [\(.id)]"' \
            "$TMPDIR/${name}.json"
        '';
    in
    {
      # The app-* checks only build the apps, so a mistyped property, id or
      # import would otherwise show up only at runtime.
      checks.qmllint =
        pkgs.runCommand "birdland-qmllint"
          {
            nativeBuildInputs = [
              qtdeclarative
              pkgs.jq
            ];
            # Qt otherwise complains about the build's "C" locale on every run.
            LANG = "C.UTF-8";
          }
          ''
            failed=0
            ${lib.concatMapStrings (name: lint name [ "${name}/*.qml" ]) apps}
            ${lint "bullpen" [ "modules/*/*.qml" ]}
            [ "$failed" = 0 ]
            touch $out
          '';
    };
}
