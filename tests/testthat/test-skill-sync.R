test_that("skill bundles share the cross-language exact-byte hash", {
  fixture <- jsonlite::fromJSON(test_path("skill-fixtures", "skill-bundle-v1.json"), simplifyVector = FALSE)
  expect_identical(.skill_hash(fixture$bundle), fixture$hash)
  expect_identical(.skill_hash(rev(fixture$bundle)), fixture$hash)
  root <- tempfile(); dir.create(root)
  .skill_install(root, ".agents/skills/example", fixture$bundle, NULL)
  folder <- file.path(root, ".agents/skills/example")
  expect_identical(.skill_hash(.skill_scan(folder)), fixture$hash)
  expect_identical(readBin(file.path(folder, "scripts/run.bin"), "raw", n = 5), as.raw(c(0,255,1,13,10)))
  writeLines("secret", file.path(folder, ".env"))
  files <- Filter(function(f) f$path != "scripts/run.bin", fixture$bundle)
  .skill_install(root, ".agents/skills/example", files, fixture$hash)
  expect_false(file.exists(file.path(folder, "scripts/run.bin")))
  expect_true(file.exists(file.path(folder, ".env")))
  for (path in c("../escape", ".env", "x/.env.local", "secret.pem", "SKILL.md/child")) {
    expect_error(.skill_hash(c(fixture$bundle, list(list(path = path, content = "", executable = FALSE)))))
  }
})

test_that("text skill files hash with LF line endings and binary files hash raw", {
  fixture <- jsonlite::fromJSON(test_path("skill-fixtures", "skill-bundle-crlf.json"), simplifyVector = FALSE)
  expect_identical(.skill_hash(fixture$lf), fixture$hash)
  expect_identical(.skill_hash(fixture$crlf), fixture$hash)
  expect_identical(.skill_hash(fixture$binary_lf), fixture$binary_lf_hash)
  # A package skill that git checked out with CRLF is still current
  root <- tempfile(); dir.create(root)
  source <- tempfile(); dir.create(source)
  writeLines(c("---", "name: example", "description: Example", "---", "First"), file.path(source, "SKILL.md"))
  expect_true(.skill_package_install(source, root, ".agents/skills/example", "example"))
  skill <- file.path(root, ".agents/skills/example/SKILL.md")
  writeBin(charToRaw(gsub("\n", "\r\n", rawToChar(readBin(skill, "raw", 1000)))), skill)
  expect_identical(.skill_package_status(source, root, ".agents/skills/example", "example"), "current")
})

test_that("package updates preserve edited and untracked skills", {
  root <- tempfile(); dir.create(root)
  source <- tempfile(); dir.create(source)
  writeLines(c("---", "name: example", "description: Example", "---", "First"), file.path(source,"SKILL.md"))
  expect_true(.skill_package_install(source, root, ".agents/skills/example", "example"))
  expect_true(.skill_package_install(source, root, ".claude/skills/example", "example"))
  local <- file.path(root,".agents/skills/example/SKILL.md")
  cat("Personal edit\n", file = local, append = TRUE)
  writeLines("Package changed", file.path(source,"SKILL.md"))
  expect_false(.skill_package_install(source, root, ".agents/skills/example", "example"))
  expect_match(paste(readLines(local),collapse="\n"),"Personal edit")
  state <- .skill_load(root)
  expect_length(state$skills[[1]]$paths, 2)
})

test_that("skill synchronization handles push, pull, dry-run, and conflicts", {
  root <- tempfile(); dir.create(root)
  folder <- file.path(root,".agents/skills/example"); dir.create(folder, recursive=TRUE)
  writeLines(c("---","name: example","description: Examples","---","First"),file.path(folder,"SKILL.md"))
  remote <- NULL; calls <- 0L
  local_mocked_bindings(.fw_cloud_url = function() "https://cloud.example", .fw_require_token = function(...) "token",
    .fw_api = function(path, token, method="GET", body=NULL, ...) {
      if (identical(method,"GET")) return(remote)
      calls <<- calls + 1L
      expect_equal(body$expected_version, if (is.null(remote)) 0L else remote$version)
      remote <<- list(skill_id="private-id",version=if(is.null(remote))1L else remote$version+1L,bundle=body$bundle,hash=.skill_hash(body$bundle))
      remote
    })
  expect_identical(skills_sync(".agents/skills/example",root,dry_run=TRUE)$action,"push")
  expect_null(remote); expect_false(file.exists(file.path(root,".framework/skills.lock.json")))
  expect_identical(skills_sync(".agents/skills/example",root)$action,"push")
  expect_equal(calls,1L)
  remote$bundle[[1]]$content <- jsonlite::base64_enc(charToRaw("Web edit\n"));remote$hash <- .skill_hash(remote$bundle);remote$version<-2L
  expect_identical(skills_sync(".agents/skills/example",root)$action,"pull")
  expect_identical(readLines(file.path(folder,"SKILL.md")),"Web edit")
  writeLines("Local edit",file.path(folder,"SKILL.md"))
  remote$bundle[[1]]$content <- jsonlite::base64_enc(charToRaw("Another web edit\n"));remote$hash<-.skill_hash(remote$bundle);remote$version<-3L
  expect_identical(skills_sync(".agents/skills/example",root)$action,"conflict")
  expect_identical(readLines(file.path(folder,"SKILL.md")),"Local edit")
  expect_identical(skills_sync(".agents/skills/example",root,resolve="local")$action,"push")
  expect_equal(remote$version,4L)
})
