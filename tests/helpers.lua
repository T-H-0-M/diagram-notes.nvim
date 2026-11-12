local M = { passed = 0, failed = 0 }

function M.equal(expected, actual)
	assert(vim.deep_equal(expected, actual), "Expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end

function M.test(name, body, cleanup)
	local ok, err = xpcall(body, debug.traceback)
	if cleanup then
		cleanup()
	end
	if ok then
		M.passed = M.passed + 1
		print("PASS " .. name)
	else
		M.failed = M.failed + 1
		io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n")
	end
end

function M.finish()
	print(("%d passed, %d failed"):format(M.passed, M.failed))
	vim.cmd(M.failed == 0 and "qa!" or "cquit 1")
end

return M
