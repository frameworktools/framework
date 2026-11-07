<template>
  <div class="flex min-h-screen">
    <!-- Sidebar -->
    <nav class="w-64 shrink-0 border-r border-gray-200 p-6 dark:border-gray-800">
      <h2 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">New Project Defaults</h2>

      <div class="space-y-1">
        <div v-for="section in sections" :key="section.id">
          <!-- Insert SETTINGS heading before Basics -->
          <NavigationSectionHeading v-if="section.id === 'basics'">Settings</NavigationSectionHeading>

          <a
            :href="buildSettingsHref(section.slug)"
            @click.prevent="navigateToSection(section.id)"
            :class="[
              'flex items-center gap-2 px-3 py-2 rounded-md text-sm transition',
              isSectionActive(section.id)
                ? 'bg-sky-50 text-sky-700 font-medium dark:bg-sky-900/20 dark:text-sky-400'
                : 'text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-gray-800'
            ]"
          >
            <component v-if="section.icon" :is="section.icon" class="h-4 w-4" />
            <svg
              v-else-if="section.svgIcon"
              class="h-4 w-4"
              :fill="section.svgFill ?? 'none'"
              :viewBox="section.svgViewBox ?? '0 0 24 24'"
              :stroke="section.svgStroke ?? 'currentColor'"
            >
              <path
                :stroke-linecap="section.svgStrokeLinecap ?? 'round'"
                :stroke-linejoin="section.svgStrokeLinejoin ?? 'round'"
                :stroke-width="section.svgStrokeWidth ?? 2"
                :fill="section.svgPathFill ?? 'none'"
                :d="section.svgIcon"
              />
            </svg>
            {{ section.label }}
          </a>

          <div
            v-if="section.id === 'structure' && activeSection === 'structure'"
            class="ml-4 mt-2 space-y-0.5 border-l border-gray-200 pl-3 dark:border-gray-700"
          >
            <a
              v-for="item in projectStructureSubnav"
              :key="item.key"
              :href="buildSettingsHref('project-structure', item.slug)"
              @click.prevent="navigateToProjectType(item.key)"
              :class="[
                'block rounded-md py-1 pl-4 pr-2 text-xs font-medium transition',
                currentProjectTypeKey === item.key
                  ? 'bg-sky-100 text-sky-700 dark:bg-sky-900/30 dark:text-sky-300'
                  : 'text-gray-600 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-800'
              ]"
            >
              {{ item.label }}
            </a>
          </div>

          <div
            v-else-if="section.id === 'templates' && activeSection === 'templates'"
            class="ml-4 mt-2 space-y-0.5 border-l border-gray-200 pl-3 dark:border-gray-700"
          >
            <a
              v-for="item in templatesSubnav"
              :key="item.id"
              :href="buildSettingsHref('templates', item.slug)"
              @click.prevent="navigateToTemplate(item.slug)"
              :class="[
                'block rounded-md py-1 pl-4 pr-2 text-xs font-medium transition',
                selectedTemplate === item.slug
                  ? 'bg-sky-100 text-sky-700 dark:bg-sky-900/30 dark:text-sky-300'
                  : 'text-gray-600 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-800'
              ]"
            >
              {{ item.label }}
            </a>
          </div>
        </div>

        <Modal v-model="envPreviewModal" title=".env Variables Preview">
          <p class="mb-3 text-sm text-gray-600 dark:text-gray-400">
            Copy these entries into your project’s <code>.env</code> file so the connections above resolve properly.
          </p>
          <pre class="rounded-md bg-gray-900 p-4 text-xs text-gray-200">{{ envPreviewText }}</pre>
          <div class="mt-4 flex justify-end">
            <Button variant="primary" @click="envPreviewModal = false">Close</Button>
          </div>
        </Modal>
      </div>

      <!-- Save Button in Sidebar -->
      <div class="mt-6 px-3">
        <Button
          variant="primary"
          size="md"
          :disabled="saving"
          @click="saveSettings"
          class="w-full"
        >
          {{ saving ? 'Saving…' : 'Save Changes' }}
        </Button>
      </div>
    </nav>

    <!-- Loading State -->
    <div v-if="isLoadingSettings" class="flex-1 flex items-center justify-center">
      <div class="text-center">
        <div class="inline-block h-8 w-8 animate-spin rounded-full border-4 border-solid border-sky-600 border-r-transparent"></div>
        <p class="mt-4 text-sm text-gray-600 dark:text-gray-400">Loading settings...</p>
      </div>
    </div>

    <!-- Main Content -->
    <div v-show="!isLoadingSettings" class="flex-1 p-10 pb-4">
      <PageHeader
        :title="pageHeaderTitle"
        :description="pageHeaderDescription"
      />

      <div class="mt-8 space-y-10">
        <!-- Overview -->
        <div id="overview" v-show="activeSection === 'overview'">
          <OverviewSummary
            :cards="overviewCards"
            @navigate="navigateToSection"
          />
        </div>

        <!-- Connections -->
        <div id="connections-defaults" v-show="activeSection === 'connections-defaults'">
          <!-- Tutorial/Explainer -->
          <div class="mb-6 rounded-lg border border-sky-200 bg-sky-50 p-4 dark:border-sky-800 dark:bg-sky-900/20">
            <h4 class="text-sm font-semibold text-sky-900 dark:text-sky-100 mb-2">Connection values</h4>
            <p class="text-sm text-sky-800 dark:text-sky-200 mb-2">
              Use <code class="px-1 py-0.5 bg-sky-100 dark:bg-sky-800 rounded text-xs">env("VAR_NAME", "default")</code> to read from your project's <code class="px-1 py-0.5 bg-sky-100 dark:bg-sky-800 rounded text-xs">.env</code> file.
              This keeps credentials out of version control while letting each machine use its own values.
            </p>
            <p class="text-sm text-sky-800 dark:text-sky-200">
              You can also type values directly (e.g. <code class="px-1 py-0.5 bg-sky-100 dark:bg-sky-800 rounded text-xs">localhost</code> or <code class="px-1 py-0.5 bg-sky-100 dark:bg-sky-800 rounded text-xs">5432</code>) if you don't need environment variable substitution.
            </p>
          </div>

          <ConnectionsPanel
            v-model:database-connections="databaseConnections"
            v-model:s3-connections="s3Connections"
            v-model:default-database="defaultDatabase"
            v-model:default-storage-bucket="defaultStorageBucket"
          />
        </div>

        <!-- .env Defaults -->
        <div id="env-defaults" v-show="activeSection === 'env-defaults'">
          <SettingsPanel flush>
            <!-- Tutorial/Explainer -->
            <div class="mb-6 rounded-lg border border-sky-200 bg-sky-50 p-4 dark:border-sky-800 dark:bg-sky-900/20">
              <h4 class="text-sm font-semibold text-sky-900 dark:text-sky-100 mb-2">How .env files work</h4>
              <p class="text-sm text-sky-800 dark:text-sky-200 mb-2">
                Environment variables let you keep sensitive data (passwords, API keys) separate from your code.
                Instead of hardcoding <code class="px-1 py-0.5 bg-sky-100 dark:bg-sky-800 rounded text-xs">password = "secret123"</code>,
                your code reads from a variable: <code class="px-1 py-0.5 bg-sky-100 dark:bg-sky-800 rounded text-xs">Sys.getenv("POSTGRES_PASSWORD")</code>
              </p>
              <p class="text-sm text-sky-800 dark:text-sky-200">
                The <code class="px-1 py-0.5 bg-sky-100 dark:bg-sky-800 rounded text-xs">.env</code> file is gitignored by default,
                so your secrets stay on your machine while your code can be shared safely.
              </p>
            </div>

            <EnvEditor
              :groups="defaultEnvGroups"
              v-model:variables="defaultEnvVariables"
              v-model:raw-content="defaultEnvRawContent"
              v-model:view-mode="defaultEnvViewMode"
              v-model:regroup-on-save="defaultEnvRegroup"
              :show-save-button="false"
              :allow-show-values-toggle="true"
            />

            <div class="mt-6 flex justify-end">
              <Button variant="primary" @click="saveSettings" :disabled="saving">
                {{ saving ? 'Saving…' : 'Save Changes' }}
              </Button>
            </div>
          </SettingsPanel>
        </div>

        <!-- Basics -->
        <div id="basics" v-show="activeSection === 'basics'">
          <SettingsPanel>
            <SettingsBlock>
              <div class="space-y-5">
                <Input
                  v-model="settings.projects_root"
                  label="Default Projects Directory"
                  hint="New projects will be created in this directory by default"
                  placeholder="e.g., ~/projects or /Users/yourname/code"
                />

                <EditorAndNotebookPanel
                  v-model:positron="settings.defaults.positron"
                  v-model:notebook-format="settings.defaults.notebook_format"
                />

                <!-- Author Information -->
                <div class="pt-4 border-t border-gray-200 dark:border-gray-700">
                  <AuthorInformationPanel v-model="settings.author" />
                </div>
              </div>
            </SettingsBlock>
          </SettingsPanel>

        </div>

        <!-- Project Structure -->
        <div id="structure" v-show="activeSection === 'structure'" class="space-y-8">
          <!-- Index page when no project type is selected -->
          <div v-if="!currentProjectTypeKey" class="space-y-6">

            <div class="space-y-3">
              <button
                v-for="item in projectStructureSubnav"
                :key="item.key"
                @click="navigateToProjectType(item.key)"
                class="group relative w-full rounded-lg border border-gray-200 p-6 text-left transition hover:border-sky-300 dark:border-gray-700 dark:hover:border-sky-600"
              >
                <div class="flex items-start gap-3">
                  <FolderIcon class="h-6 w-6 flex-shrink-0 text-gray-400 transition group-hover:text-sky-600 dark:group-hover:text-sky-400" />
                  <div>
                    <h3 class="font-semibold text-gray-900 dark:text-white">
                      {{ item.label }}
                    </h3>
                    <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
                      {{ settings.project_types[item.key]?.description || '' }}
                    </p>
                  </div>
                </div>
              </button>
            </div>
          </div>

          <!-- Project type editor when a type is selected -->
          <div v-else-if="currentProjectType && catalog">
            <ProjectStructureEditor
              :project-type="currentProjectTypeKey"
              v-model:directories="settings.project_types[currentProjectTypeKey].directories"
              v-model:render-dirs="settings.project_types[currentProjectTypeKey].render_dirs"
              v-model:enabled="directoriesEnabled[currentProjectTypeKey]"
              v-model:extra-directories="settings.project_types[currentProjectTypeKey].extra_directories"
              v-model:settings="settings.project_types[currentProjectTypeKey]"
              v-model:gitignore="settings.project_types[currentProjectTypeKey].gitignore"
              :catalog="catalog.project_types[currentProjectTypeKey] || {}"
              :new-extra-ids="newExtraDirectoryIds"
              @update:newExtraIds="newExtraDirectoryIds = $event"
              @reset="showResetConfirm(currentProjectTypeKey)"
            />
          </div>
        </div>

        <!-- Git & Hooks -->
        <div id="git" v-show="activeSection === 'git'">
          <SettingsPanel>
            <GitHooksPanel v-model="gitPanelModel" flush>
              <template #note>
                Project-specific .gitignore templates can be customized in <a href="#/settings/project-defaults" class="text-sky-600 dark:text-sky-400 hover:underline">Project Defaults</a>.
              </template>
            </GitHooksPanel>
          </SettingsPanel>
        </div>

        <div id="scaffold" v-show="activeSection === 'scaffold'">
          <SettingsPanel>
            <div>
              <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">Scaffold Behavior</h3>
              <p class="text-sm text-gray-600 dark:text-gray-400 mb-6">
                Automatic actions when <code class="px-1.5 py-0.5 bg-gray-200 dark:bg-gray-700 rounded text-xs">scaffold()</code> runs to initialize your project environment.
              </p>
            </div>

            <ScaffoldBehaviorPanel v-model="scaffoldPanelModel" flush />
          </SettingsPanel>
        </div>

        <!-- Packages -->
        <div id="packages" v-show="activeSection === 'packages'">
          <PackagesEditor
            v-model="defaultPackagesModel"
            :show-renv-toggle="true"
          />
        </div>

        <!-- Quarto -->
        <div id="quarto" v-show="activeSection === 'quarto'">
          <SettingsPanel flush>
            <QuartoSettingsPanel v-model="settings.defaults.quarto" />
          </SettingsPanel>
        </div>

        <!-- AI Assistants -->
        <div id="ai" v-show="activeSection === 'ai'">
          <SettingsPanel>
            <p class="text-sm text-gray-600 dark:text-gray-400 mb-6">
              Manage assistant support, canonical context files, and sync hooks for all new projects.
            </p>
            <AIAssistantsPanel
              v-model="defaultAiModel"
              :flush="true"
              :show-editor="true"
              editor-height="420px"
            >
              <template #editor-actions>
                <div class="mt-4 flex justify-end">
                  <Button size="sm" variant="secondary" @click="openCanonicalTemplate">
                    Open canonical file
                  </Button>
                </div>
              </template>
            </AIAssistantsPanel>
          </SettingsPanel>
        </div>

        <!-- Templates -->
        <div id="templates" v-show="activeSection === 'templates'">
          <SettingsPanel flush>
            <div class="flex flex-wrap gap-2 mb-6">
              <button
                v-for="tab in templateTabs"
                :key="tab.key"
                type="button"
                @click="navigateToTemplate(tab.key)"
                class="px-3 py-1.5 rounded-full text-sm font-medium border transition"
                :class="selectedTemplate === tab.key
                  ? 'bg-sky-100 text-sky-700 border-sky-300 dark:bg-sky-900/30 dark:text-sky-200 dark:border-sky-700'
                  : 'text-gray-700 border-gray-200 hover:border-sky-300 hover:text-sky-700 dark:text-gray-300 dark:border-gray-700 dark:hover:text-sky-200'"
              >
                {{ tab.label }}
              </button>
            </div>

            <div class="flex flex-col gap-4">
              <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
                <div class="space-y-1">
                  <h4 class="text-base font-semibold text-gray-900 dark:text-white">
                    {{ currentTemplateTab.label }} Template
                  </h4>
                  <p class="text-sm text-gray-600 dark:text-gray-400">
                    {{ currentTemplateTab.description }}
                  </p>
                  <p class="text-xs text-gray-500 dark:text-gray-500">
                    Edits save with the main "Save Changes" button.
                  </p>
                </div>
                <Button
                  size="sm"
                  variant="secondary"
                  :disabled="templateEditors[currentTemplateTab.editorKey].loading"
                  @click="resetCurrentTemplate($event)"
                >
                  Reset to default
                </Button>
              </div>

              <!-- Template Variables Legend -->
              <div v-if="currentTemplateTab.hasVariables" class="rounded-md bg-sky-50 dark:bg-sky-900/20 border border-sky-200 dark:border-sky-800 p-3">
                <h5 class="text-xs font-semibold text-sky-800 dark:text-sky-300 mb-2">Available Variables</h5>
                <table class="text-xs">
                  <tbody>
                    <tr v-for="variable in templateVariables" :key="variable.syntax">
                      <td class="font-mono font-medium text-sky-700 dark:text-sky-300 pr-4 py-0.5">{{ variable.syntax }}</td>
                      <td class="text-gray-600 dark:text-gray-400 py-0.5">{{ variable.description }}</td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <CodeEditor
                v-model="templateEditors[currentTemplateTab.editorKey].contents"
                :language="currentTemplateTab.language"
                auto-grow
              />
            </div>
          </SettingsPanel>
        </div>

      </div>

    </div>

    <!-- Reset to Defaults Confirmation Modal -->
    <Modal v-model="resetConfirmModal.open" size="md" title="Reset to Defaults" icon="warning">
      <template #default>
        <p class="text-sm text-gray-600 dark:text-gray-300">
          Are you sure you want to reset <strong>{{ resetConfirmModal.projectTypeName }}</strong> to default settings?
          This will discard all your customizations for this project type.
        </p>
      </template>
      <template #actions>
        <div class="flex gap-3 justify-end">
          <Button variant="secondary" @click="resetConfirmModal.open = false">Cancel</Button>
          <Button variant="primary" @click="resetProjectType">
            Reset to Defaults
          </Button>
        </div>
      </template>
    </Modal>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import PageHeader from '../components/ui/PageHeader.vue'
import Input from '../components/ui/Input.vue'
import Select from '../components/ui/Select.vue'
import Toggle from '../components/ui/Toggle.vue'
import Checkbox from '../components/ui/Checkbox.vue'
import Button from '../components/ui/Button.vue'
import CopyButton from '../components/ui/CopyButton.vue'
import OverviewCard from '../components/ui/OverviewCard.vue'
import OverviewSummary from '../components/OverviewSummary.vue'
import NavigationSectionHeading from '../components/ui/NavigationSectionHeading.vue'
import Modal from '../components/ui/Modal.vue'
import CodeEditor from '../components/ui/CodeEditor.vue'
import Repeater from '../components/ui/Repeater.vue'
import { useToast } from '../composables/useToast'
import SettingsPanel from '../components/settings/SettingsPanel.vue'
import SettingsBlock from '../components/settings/SettingsBlock.vue'
import ConnectionsPanel from '../components/settings/ConnectionsPanel.vue'
import GitHooksPanel from '../components/settings/GitHooksPanel.vue'
import ScaffoldBehaviorPanel from '../components/settings/ScaffoldBehaviorPanel.vue'
import AuthorInformationPanel from '../components/settings/AuthorInformationPanel.vue'
import EditorAndNotebookPanel from '../components/settings/EditorAndNotebookPanel.vue'
import ProjectStructureEditor from '../components/settings/ProjectStructureEditor.vue'
import QuartoSettingsPanel from '../components/settings/QuartoSettingsPanel.vue'
import EnvEditor from '../components/env/EnvEditor.vue'
import PackagesEditor from '../components/settings/PackagesEditor.vue'
import AIAssistantsPanel from '../components/settings/AIAssistantsPanel.vue'
import {
  normalizeDefaultPackages,
  mapDefaultPackagesToPayload
} from '../utils/packageHelpers'
import {
  parseEnvContent,
  groupEnvByPrefix,
  normalizeEnvConfig,
  DEFAULT_ENV_TEMPLATE
} from '../utils/envHelpers'
import {
  mapConnectionsToArrays,
  mapConnectionsToPayload
} from '../utils/connectionHelpers'
import {
  normalizeDirectoriesFromCatalog,
  normalizeRenderDirsFromCatalog
} from '../utils/structureHelpers'
import {
  hydrateStructureFromCatalog,
  serializeStructureForSave
} from '../utils/structureMapping'
import { buildGitPanelModel, applyGitPanelModel } from '../utils/gitHelpers'
import {
  InformationCircleIcon,
  UserIcon,
  Cog6ToothIcon,
  CubeIcon,
  DocumentTextIcon,
  FolderIcon,
  KeyIcon,
  ServerStackIcon
} from '@heroicons/vue/24/outline'

const toast = useToast()
const router = useRouter()
const route = useRoute()

const sections = [
  { id: 'overview', label: 'Overview', slug: 'overview', icon: InformationCircleIcon },
  { id: 'basics', label: 'Basics', slug: 'basics', icon: Cog6ToothIcon },
  { id: 'structure', label: 'Project Structure', slug: 'project-structure', icon: FolderIcon },
  { id: 'packages', label: 'Packages', slug: 'packages-dependencies', icon: CubeIcon },
  { id: 'quarto', label: 'Quarto', slug: 'quarto', icon: DocumentTextIcon },
  { id: 'git', label: 'Git & Hooks', slug: 'git-hooks', svgIcon: 'M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4' },
  { id: 'ai', label: 'AI Assistants', slug: 'ai-assistants', svgIcon: 'M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z' },
  {
    id: 'scaffold',
    label: 'Scaffold Behavior',
    slug: 'scaffold-behavior',
    svgIcon:
      'M256 64L576 64L576 576L64 576L64 192L256 192L256 64zM256 224L96 224L96 544L256 544L256 224zM288 544L544 544L544 96L288 96L288 544zM440 152L488 152L488 200L440 200L440 152zM392 152L392 200L344 200L344 152L392 152zM440 248L488 248L488 296L440 296L440 248zM392 248L392 296L344 296L344 248L392 248zM152 280L200 280L200 328L152 328L152 280zM392 344L392 392L344 392L344 344L392 344zM152 376L200 376L200 424L152 424L152 376zM488 344L488 392L440 392L440 344L488 344z',
    svgViewBox: '0 0 640 640',
    svgFill: 'currentColor',
    svgStroke: 'none',
    svgStrokeWidth: 0,
    svgPathFill: 'currentColor'
  },
  { id: 'templates', label: 'Templates', slug: 'templates', icon: DocumentTextIcon },
  { id: 'connections-defaults', label: 'Connections', slug: 'connections', icon: ServerStackIcon },
  { id: 'env-defaults', label: '.env Defaults', slug: 'env', icon: KeyIcon }
]

const sectionSlugMap = Object.fromEntries(sections.map(({ id, slug }) => [id, slug]))
const sectionSlugToId = Object.fromEntries(sections.map(({ id, slug }) => [slug, id]))
const defaultSectionId = 'overview'

const fallbackProjectTypes = {
  project: {
    label: 'Standard Project Structure',
    description: 'General-purpose analysis project with notebooks, scripts, and shared outputs.',
    directories: {
      functions: 'R/functions',
      notebooks: 'notebooks',
      scripts: 'scripts',
      inputs_raw: 'inputs/raw',
      inputs_intermediate: 'inputs/intermediate',
      inputs_final: 'inputs/final',
      docs: 'docs',
      outputs_tables: 'outputs/tables',
      outputs_figures: 'outputs/figures',
      outputs_models: 'outputs/models',
      outputs_reports: 'outputs/reports',
      cache: 'outputs/cache',
      scratch: 'scratch'
    },
    render_dirs: {
      notebooks: 'outputs/notebooks',
      docs: 'outputs/docs'
    },
    quarto: { render_dir: 'outputs/notebooks' },
    notebook_template: 'notebook',
    extra_directories: []
  },
  project_sensitive: {
    label: 'Privacy Sensitive Project Structure',
    description: 'Projects handling PHI/PII with dedicated private/public data flows.',
    directories: {
      functions: 'R/functions',
      notebooks: 'notebooks',
      scripts: 'scripts',
      inputs_private_raw: 'inputs/private/raw',
      inputs_private_intermediate: 'inputs/private/intermediate',
      inputs_private_final: 'inputs/private/final',
      inputs_public_raw: 'inputs/public/raw',
      inputs_public_intermediate: 'inputs/public/intermediate',
      inputs_public_final: 'inputs/public/final',
      outputs_private_tables: 'outputs/private/tables',
      outputs_private_figures: 'outputs/private/figures',
      outputs_private_models: 'outputs/private/models',
      outputs_private_docs: 'outputs/private/docs',
      outputs_private_data_final: 'outputs/private/data_final',
      outputs_public_tables: 'outputs/public/tables',
      outputs_public_figures: 'outputs/public/figures',
      outputs_public_models: 'outputs/public/models',
      outputs_public_docs: 'outputs/public/docs',
      outputs_public_data_final: 'outputs/public/data_final',
      cache: 'outputs/private/cache',
      scratch: 'scratch'
    },
    quarto: { render_dir: 'outputs/private/notebooks' },
    notebook_template: 'notebook',
    extra_directories: []
  },
  presentation: {
    label: 'Presentation Structure',
    description: 'Single talk or slide deck with minimal analysis scaffolding.',
    directories: {
      presentation_source: 'presentation.qmd',
      rendered_slides: '.',
      cache: 'cache'
    },
    quarto: { render_dir: '.' },
    notebook_template: 'notebook',
    extra_directories: []
  },
  course: {
    label: 'Course Structure',
    description: 'Courses with modules, assignments, and lecture materials.',
    directories: {
      data: 'data',
      slides: 'slides',
      assignments: 'assignments',
      course_docs: 'course_docs',
      readings: 'readings',
      notebooks: 'modules',
      cache: 'cache'
    },
    quarto: { render_dir: 'course_docs' },
    notebook_template: 'notebook',
    extra_directories: []
  }
}

const defaultProjectTypes = ref(JSON.parse(JSON.stringify(fallbackProjectTypes)))

const projectTypeSlugMap = {
  project: 'project',
  project_sensitive: 'sensitive-project',
  presentation: 'presentation',
  course: 'course'
}

const projectSlugToKey = Object.fromEntries(Object.entries(projectTypeSlugMap).map(([key, slug]) => [slug, key]))
const defaultProjectTypeKey = 'project'

const defaultProjectDescriptions = {
  project: 'Tune the standard analysis layout—functions, notebooks, inputs, and outputs live here by default.',
  project_sensitive: 'Private and public inputs stay separate so sensitive data never leaves restricted folders.',
  presentation: 'Control where your presentation source lives and where rendered slides are written.',
  course: 'Adjust the folders used for slides, assignments, readings, and course documentation.'
}

const formatProjectTypeName = (key) => String(key).replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())

const catalog = ref(null)

// Workspace directories that support Quarto rendering
const generalWorkspaceRenderableFallback = [
  {
    key: 'notebooks',
    label: 'Notebooks',
    hint: 'Quarto or R Markdown notebooks for analysis.',
    defaultRenderDir: 'outputs/notebooks'
  },
  {
    key: 'docs',
    label: 'Documentation',
    hint: 'Codebooks, documentation, and other reference materials.',
    defaultRenderDir: 'outputs/docs'
  }
]

// Workspace directories without Quarto rendering
const generalWorkspaceNonRenderableFallback = [
  {
    key: 'functions',
    label: 'Functions',
    hint: 'R files here are sourced by scaffold(), so helper functions are available in every project session.'
  },
  {
    key: 'scripts',
    label: 'Scripts',
    hint: 'Reusable R scripts, job runners, or automation tasks.'
  }
]

// Combined for compatibility
const generalWorkspaceFallback = [
  ...generalWorkspaceRenderableFallback,
  ...generalWorkspaceNonRenderableFallback
]

const generalInputFallback = [
  { key: 'inputs_raw', label: 'Raw data', hint: 'Read-only exports from source systems.' },
  { key: 'inputs_intermediate', label: 'Intermediate data', hint: 'Data after light cleaning or pre-processing steps.' },
  { key: 'inputs_final', label: 'Analysis-ready data', hint: 'Final inputs ready for modeling or reporting.' }
]

const generalOutputFallback = [
  { key: 'outputs_tables', label: 'Tables', hint: 'Publishable tables ready for reports or manuscripts.' },
  { key: 'outputs_figures', label: 'Figures', hint: 'Final plots and graphics.' },
  { key: 'outputs_models', label: 'Models', hint: 'Serialized models or model summaries.' },
  { key: 'outputs_reports', label: 'Reports', hint: 'Final reports and deliverables ready for publication.' }
]

const generalUtilityFallback = [
  { key: 'scratch', label: 'Scratch', hint: 'Short-lived explorations (gitignored).' }
]

const sensitiveInputFallback = [
  { privateKey: 'inputs_private_raw', publicKey: 'inputs_public_raw', label: 'Raw data', privateLabel: 'Raw data (private)', publicLabel: 'Raw data (public)', hint: 'Read-only exports from source systems.' },
  { privateKey: 'inputs_private_intermediate', publicKey: 'inputs_public_intermediate', label: 'Intermediate data', privateLabel: 'Intermediate data (private)', publicLabel: 'Intermediate data (public)', hint: 'Data after light cleaning or pre-processing steps.' },
  { privateKey: 'inputs_private_final', publicKey: 'inputs_public_final', label: 'Analysis-ready data', privateLabel: 'Analysis-ready data (private)', publicLabel: 'Analysis-ready data (public)', hint: 'Final inputs ready for modeling or reporting.' }
]

const sensitiveOutputFallback = [
  { privateKey: 'outputs_private_tables', publicKey: 'outputs_public_tables', label: 'Tables', privateLabel: 'Tables (private)', publicLabel: 'Tables (public)', hint: 'Publishable tables ready for reports or manuscripts.' },
  { privateKey: 'outputs_private_figures', publicKey: 'outputs_public_figures', label: 'Figures', privateLabel: 'Figures (private)', publicLabel: 'Figures (public)', hint: 'Final plots and graphics.' },
  { privateKey: 'outputs_private_models', publicKey: 'outputs_public_models', label: 'Models', privateLabel: 'Models (private)', publicLabel: 'Models (public)', hint: 'Serialized models or model summaries.' },
  { privateKey: 'outputs_private_reports', publicKey: 'outputs_public_reports', label: 'Reports', privateLabel: 'Reports (private)', publicLabel: 'Reports (public)', hint: 'Final reports and deliverables ready for publication.' }
]

const getDirectoryMeta = (typeKey, dirKey) => catalog.value?.project_types?.[typeKey]?.directories?.[dirKey] || {}

const buildDirectoryFields = (typeKey, fallback) =>
  fallback.map((entry) => {
    const meta = getDirectoryMeta(typeKey, entry.key)
    return {
      key: entry.key,
      label: meta.label || entry.label,
      hint: meta.hint || entry.hint || ''
    }
  })

const generalWorkspaceFields = computed(() => buildDirectoryFields('project', generalWorkspaceFallback))
const generalWorkspaceRenderableFields = computed(() => buildDirectoryFields('project', generalWorkspaceRenderableFallback).map(field => ({
  ...field,
  defaultRenderDir: generalWorkspaceRenderableFallback.find(f => f.key === field.key)?.defaultRenderDir || ''
})))
const generalWorkspaceNonRenderableFields = computed(() => buildDirectoryFields('project', generalWorkspaceNonRenderableFallback))
const generalInputFields = computed(() => buildDirectoryFields('project', generalInputFallback))
const generalOutputFields = computed(() => buildDirectoryFields('project', generalOutputFallback))
const generalUtilityFields = computed(() => buildDirectoryFields('project', generalUtilityFallback))

const buildSensitivePairs = (fallback) =>
  fallback.map((entry) => {
    const privateMeta = getDirectoryMeta('project_sensitive', entry.privateKey)
    const publicMeta = getDirectoryMeta('project_sensitive', entry.publicKey)
    return {
      ...entry,
      privateLabel: privateMeta.label || entry.privateLabel,
      publicLabel: publicMeta.label || entry.publicLabel
    }
  })

const sensitiveInputPairs = computed(() => buildSensitivePairs(sensitiveInputFallback))
const sensitiveOutputPairs = computed(() => buildSensitivePairs(sensitiveOutputFallback))

const currentProjectTypeSettings = computed(() => {
  const key = currentProjectTypeKey.value
  if (!key || !catalog.value?.project_types?.[key]?.settings) return []
  return catalog.value.project_types[key].settings
})

const presentationToggleFallbacks = {
  include_inputs: 'data',
  include_scripts: 'scripts',
  include_functions: 'functions'
}

const presentationOptionalDefaults = computed(() => {
  const toggles = catalog.value?.project_types?.presentation?.optional_toggles || {}
  return {
    inputs: toggles.include_inputs?.default_path || presentationToggleFallbacks.include_inputs,
    scripts: toggles.include_scripts?.default_path || presentationToggleFallbacks.include_scripts,
    functions: toggles.include_functions?.default_path || presentationToggleFallbacks.include_functions
  }
})

const canonicalTemplateMap = {
  'CLAUDE.md': 'ai_claude',
  'AGENTS.md': 'ai_agents',
  '.github/copilot-instructions.md': 'ai_copilot'
}

const availableAssistants = [
  { id: 'claude', label: 'Claude Code', description: "Anthropic's IDE-focused assistant." },
  { id: 'copilot', label: 'GitHub Copilot', description: 'Complements VS Code and JetBrains editors.' },
  { id: 'agents', label: 'Multi-Agent (OpenAI Codex, Cursor, etc.)', description: 'Shared instructions for multi-model orchestrators.' }
]

const activeSection = ref(defaultSectionId)
const saving = ref(false)

// Track new (unsaved) extra_directories by their _id
const newExtraDirectoryIds = ref(new Set())

const settings = ref({
  projects_root: '',
  project_types: JSON.parse(JSON.stringify(defaultProjectTypes.value)),
  author: {
    name: '',
    email: '',
    affiliation: ''
  },
  defaults: {
    project_type: 'project',
    notebook_format: 'quarto',
    ide: 'vscode',
    positron: false,
    use_git: true,
    use_renv: false,
    seed: '123',
    seed_on_scaffold: false,
    ai_support: true,
    ai_assistants: ['claude'],
    ai_canonical_file: 'CLAUDE.md',
    scaffold: {
      source_all_functions: true,
      set_theme_on_scaffold: false,
      ggplot_theme: 'theme_minimal',
      seed_on_scaffold: false,
      seed: '123'
    },
    directories: JSON.parse(JSON.stringify(defaultProjectTypes.value.project.directories)),
    git_hooks: {
      ai_sync: false,
      data_security: false,
      check_sensitive_dirs: false
    },
    packages: {
      use_renv: false,
      default_packages: [
        { name: 'dplyr', source: 'cran', auto_attach: false },
        { name: 'ggplot2', source: 'cran', auto_attach: false },
        { name: 'readr', source: 'cran', auto_attach: false }
      ]
    },
    quarto: {
      html: {
        format: 'html',
        embed_resources: true,
        theme: 'default',
        toc: true,
        toc_depth: 3,
        code_fold: false,
        code_tools: false,
        highlight_style: 'github'
      },
      revealjs: {
        format: 'revealjs',
        theme: 'default',
        incremental: false,
        slide_number: true,
        transition: 'slide',
        background_transition: 'fade',
        controls: true,
        progress: true,
        center: true,
        highlight_style: 'github'
      }
    },
    env: {
      raw: ''
    }
    // connections: {
    //   options: { default_connection: 'framework' },
    //   connections: {
    //     framework: {
    //       driver: 'sqlite',
    //       database: 'env("FRAMEWORK_DB_PATH", "framework.db")'
    //     }
    //   }
    // }
  },
  git: {
    user_name: '',
    user_email: ''
  },
  privacy: {
    secret_scan: false,
    gitignore_template: 'gitignore'
  }
})

const presentationOptions = reactive({
  includeInputs: false,
  includeScripts: false,
  includeFunctions: false
})

// Reactive state for directory toggles across all project types
const directoriesEnabled = reactive({
  project: {},
  project_sensitive: {},
  course: {},
  presentation: {}
})

// Helper function to safely access directories_enabled for a project type
const getDirectoriesEnabled = (projectType) => {
  if (!directoriesEnabled[projectType]) {
    directoriesEnabled[projectType] = {}
  }
  return directoriesEnabled[projectType]
}

// Helper function to set directory enabled state with proper Vue reactivity
const setDirectoryEnabled = (projectTypeKey, key, value) => {
  if (!directoriesEnabled[projectTypeKey]) {
    directoriesEnabled[projectTypeKey] = {}
  }

  directoriesEnabled[projectTypeKey][key] = value
  console.log(`[Toggle] Set ${key} to ${value}`)
}

const isLoadingSettings = ref(false)

const aiAssistants = reactive({
  claude: true,
  agents: false,
  copilot: false
})

// .env defaults
const defaultEnvRawContent = ref('')
const defaultEnvVariables = ref({})
const defaultEnvViewMode = ref('grouped')
const defaultEnvRegroup = ref(false)
const defaultEnvGroups = ref({})
const envPreviewModal = ref(false)
const defaultEnvVariableCount = computed(() => Object.keys(defaultEnvVariables.value || {}).length)

// Packages model for defaults via shared editor
const defaultPackagesModel = computed({
  get() {
    return normalizeDefaultPackages(settings.value.defaults.packages)
  },
  set(val) {
    settings.value.defaults.packages = val || { use_renv: false, default_packages: [] }
  }
})

// Helper to get project type label
const getProjectTypeLabel = (type) => {
  return catalog.value?.project_types?.[type]?.label || type
}

// Overview data for OverviewSummary component
const overviewCards = computed(() => {
  const path = settings.value.projects_root || ''
  const author = settings.value.author?.name || ''
  const projectType = settings.value.defaults?.project_type || 'project'
  const projectTypeLabel = getProjectTypeLabel(projectType)
  const notebookFormat = settings.value.defaults?.notebook_format || 'quarto'
  const aiEnabled = settings.value.ai_config?.enabled || false
  const aiProvider = settings.value.ai_config?.provider || ''
  const aiCanonical = settings.value.ai_config?.canonical_file || ''
  const gitInit = settings.value.git?.auto_init || false
  const packagesCount = defaultPackagesModel.value?.default_packages?.length || 0
  const envCount = defaultEnvVariableCount.value

  return [
    {
      id: 'basics',
      title: 'Basics',
      section: 'basics',
      content: `${path} · ${author}`
    },
    {
      id: 'structure',
      title: 'Project Structure',
      section: 'structure',
      content: projectTypeLabel
    },
    {
      id: 'notebooks',
      title: 'Notebooks & Scripts',
      section: 'scaffold',
      content: notebookFormat
    },
    {
      id: 'packages',
      title: 'Packages',
      section: 'packages',
      content: packagesCount === 0 ? 'No default packages' : `${packagesCount} packages`
    },
    {
      id: 'env',
      title: '.env Defaults',
      section: 'env-defaults',
      content: `${envCount} variables`
    },
    {
      id: 'ai',
      title: 'AI Assistants',
      section: 'ai',
      content: aiEnabled
        ? `${aiProvider} · ${aiCanonical}`
        : 'Disabled'
    },
    {
      id: 'git',
      title: 'Git & Hooks',
      section: 'git',
      content: gitInit ? 'Auto-initialize repositories' : 'Manual initialization'
    }
  ]
})

// Database connections as array for repeater (framework_db is implicit/reserved)
const databaseConnections = ref([])

// S3 connections as array for repeater
const s3Connections = ref([])

// Default connections
const defaultDatabase = ref(null)
const defaultStorageBucket = ref(null)

// Auto-select default database when there's exactly one connection
// Also handles case where current default was deleted
watch(databaseConnections, (connections) => {
  const currentDefault = defaultDatabase.value
  const defaultStillExists = connections.some(c => c.name === currentDefault)

  // If only one connection, it should be the default
  if (connections.length === 1) {
    const firstConn = connections[0]
    if (firstConn?.name && firstConn.name !== 'framework_db') {
      defaultDatabase.value = firstConn.name
    }
  }
  // If current default was deleted, clear it
  else if (currentDefault && !defaultStillExists) {
    defaultDatabase.value = null
  }
}, { deep: true })

// Auto-select default S3 bucket when there's exactly one
// Also handles case where current default was deleted
watch(s3Connections, (connections) => {
  const currentDefault = defaultStorageBucket.value
  const defaultStillExists = connections.some(c => c.name === currentDefault)

  // If only one bucket, it should be the default
  if (connections.length === 1) {
    const firstConn = connections[0]
    if (firstConn?.name) {
      defaultStorageBucket.value = firstConn.name
    }
  }
  // If current default was deleted, clear it
  else if (currentDefault && !defaultStillExists) {
    defaultStorageBucket.value = null
  }
}, { deep: true })

const resetConfirmModal = reactive({
  open: false,
  projectTypeKey: null,
  projectTypeName: ''
})

const templateEditors = reactive({
  notebook: { loading: false, contents: '' },
  script: { loading: false, contents: '' },
  presentation: { loading: false, contents: '' },
  canonical: { loading: false, contents: '' }, // Used by AI Assistants panel
  gitignore_project: { loading: false, contents: '' },
  gitignore_project_sensitive: { loading: false, contents: '' },
  gitignore_course: { loading: false, contents: '' },
  gitignore_presentation: { loading: false, contents: '' }
})

// Template variables available for interpolation
const templateVariables = [
  { syntax: '{{author}}', description: 'Author name' },
  { syntax: '{{email}}', description: 'Author email' },
  { syntax: '{{affiliation}}', description: 'Author affiliation' }
]

const templateTabs = computed(() => ([
  {
    key: 'notebook',
    label: 'Notebook',
    description: 'Starter Quarto notebook used when creating notebooks.',
    editorKey: 'notebook',
    apiName: 'notebook',
    language: 'markdown',
    hasVariables: true
  },
  {
    key: 'script',
    label: 'Script',
    description: 'Starter R script used for new scripts.',
    editorKey: 'script',
    apiName: 'script',
    language: 'r',
    hasVariables: false
  },
  {
    key: 'presentation',
    label: 'Presentation',
    description: 'Starter presentation content for revealjs slides.',
    editorKey: 'presentation',
    apiName: 'presentation',
    language: 'markdown',
    hasVariables: true
  }
]))

const selectedTemplate = ref(route.params.subsection || 'notebook')

const currentTemplateTab = computed(() => {
  return templateTabs.value.find((t) => t.key === selectedTemplate.value) || templateTabs.value[0]
})

const navigateToTemplate = async (slug) => {
  selectedTemplate.value = slug || 'notebook'
  await pushSettingsRoute('templates', selectedTemplate.value)
}

const saveCurrentTemplate = async () => {
  const tab = currentTemplateTab.value
  if (!tab || !templateEditors[tab.editorKey]) return
  templateEditors[tab.editorKey].loading = true
  try {
    await fetch(`/api/templates/${tab.apiName}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contents: templateEditors[tab.editorKey].contents })
    })
    toast.success('Template Saved', `${tab.label} template updated.`)
  } catch (error) {
    toast.error('Save Failed', 'Could not save template changes.')
  } finally {
    templateEditors[tab.editorKey].loading = false
  }
}

const resetCurrentTemplate = async (event) => {
  if (event && typeof event.preventDefault === 'function') event.preventDefault()
  const tab = currentTemplateTab.value
  if (!tab) return
  const confirmed = window.confirm('Reset this template to the default packaged version?')
  if (!confirmed) return
  const editorKey = tab.editorKey
  const apiName = tab.apiName
  await resetInlineTemplate(apiName, editorKey)
}

// AI defaults model for shared panel (canonical_content sourced from template editor)
const defaultAiModel = computed({
  get() {
    const defaults = settings.value.defaults || {}
    return {
      enabled: defaults.ai_support !== false,
      canonical_file: defaults.ai_canonical_file || 'CLAUDE.md',
      assistants: Array.isArray(defaults.ai_assistants) ? [...defaults.ai_assistants] : [],
      canonical_content: templateEditors.canonical?.contents || ''
    }
  },
  set(val) {
    if (!val) return
    const defaults = settings.value.defaults || {}
    defaults.ai_support = val.enabled
    defaults.ai_canonical_file = val.canonical_file
    defaults.ai_assistants = Array.isArray(val.assistants) ? [...val.assistants] : []
    if (val.canonical_content !== undefined && templateEditors.canonical) {
      templateEditors.canonical.contents = val.canonical_content
    }
    settings.value.defaults = { ...defaults }
  }
})

const projectTypeEntries = computed(() => Object.entries(settings.value.project_types || {}))

const projectStructureSubnav = computed(() =>
  projectTypeEntries.value.map(([key, type]) => ({
    key,
    // Remove " Structure" suffix from labels for menu display
    label: (type.label || formatProjectTypeName(key)).replace(/ Structure$/i, ''),
    slug: projectTypeSlugMap[key] || key
  }))
)

const templatesSubnav = [
  { id: 'templates-notebook', label: 'Notebook', slug: 'notebook' },
  { id: 'templates-script', label: 'Script', slug: 'script' },
  { id: 'templates-presentation', label: 'Presentation', slug: 'presentation' }
]

// DISABLED - env defaults removed
// const defaultEnvGroups = computed(() => groupEnvByPrefix(defaultEnvVariables.value))

// TEMPORARILY DISABLED - connections section removed for debugging
// const databaseConnectionEntries = computed(() => {
//   const connections = editableConnections.value || {}
//   return Object.entries(connections).filter(([_, conn]) => (conn?.driver || '').toLowerCase() !== 's3')
// })

// const objectStorageConnectionEntries = computed(() => {
//   const connections = editableConnections.value || {}
//   return Object.entries(connections).filter(([_, conn]) => (conn?.driver || '').toLowerCase() === 's3')
// })

// TEMPORARILY DISABLED - connections section removed for debugging
const envPreviewText = computed(() => {
  return '# Connections section temporarily disabled for debugging'
  // const entries = {}
  // const regex = /env\(["']([^"']+)["'](?:,\s*["']([^"']*)["'])?\)/gi
  // Object.values(editableConnections.value || {}).forEach((conn) => {
  //   Object.values(conn || {}).forEach((value) => {
  //     if (typeof value !== 'string') return
  //     let match
  //     while ((match = regex.exec(value)) !== null) {
  //       const [, key, def] = match
  //       if (key && !entries[key]) {
  //         entries[key] = def ?? ''
  //       }
  //     }
  //   })
  // })
  // if (!Object.keys(entries).length) {
  //   return '# No env() references found in your connections.'
  // }
  // return Object.entries(entries)
  //   .map(([key, val]) => `${key}=${val}`)
  //   .join('\n')
})

const currentProjectTypeKey = computed(() => {
  const slug = route.params.subsection
  // Return null if no subsection to show index page
  if (!slug) return null
  return projectSlugToKey[slug] || defaultProjectTypeKey
})

const currentProjectType = computed(() => {
  const key = currentProjectTypeKey.value
  if (!key) return null
  return settings.value.project_types?.[key] || null
})

const defaultPageTitle = 'Settings'
const defaultPageDescription = 'Manage default settings for new projects.'

const sectionHeaderMeta = {
  overview: {
    title: 'Overview',
    description: 'Overview of your Framework global settings and preferences.'
  },
  'connections-defaults': {
    title: 'Connections',
    description: 'Database and storage connections that every new project will inherit.'
  },
  basics: {
    title: 'Basics',
    description: 'Essential settings for new projects.'
  },
  author: {
    title: 'Author Information',
    description: 'Defaults that populate README files and notebook headers when scaffold() runs.'
  },
  workflow: {
    title: 'Editor & Workflow',
    description: 'Control how Framework scaffolds projects in your preferred tools.'
  },
  structure: {
    title: 'Project Structure Defaults',
    description: 'Choose a project type to configure its directory structure and default settings.'
  },
  templates: {
    title: 'Templates',
    description: 'Edit the starter templates Framework uses for notebooks, scripts, and presentations.'
  },
  ai: {
    title: 'AI Assistants',
    description: 'Manage assistant support, canonical context files, and sync hooks.'
  },
  git: {
    title: 'Git & Hooks',
    description: 'Configure repository initialization, commit identity, git hooks, and security scanning.'
  },
  scaffold: {
    title: 'Scaffold Behavior',
    description: 'Automatic actions Framework performs when scaffold() runs.'
  },
  packages: {
    title: 'Packages & Dependencies',
    description: 'Define dependency defaults and auto-attach behavior for new projects.'
  },
  'env-defaults': {
    title: '.env Defaults',
    description: 'Template applied to every new project so core connections work immediately.'
  }
}

const currentSectionMeta = computed(() => sectionHeaderMeta[activeSection.value] || {
  title: defaultPageTitle,
  description: defaultPageDescription
})

const pageHeaderTitle = computed(() => {
  if (activeSection.value === 'structure' && currentProjectType.value) {
    return currentProjectType.value.label || formatProjectTypeName(currentProjectTypeKey.value)
  }
  return currentSectionMeta.value.title
})

const pageHeaderDescription = computed(() => {
  if (activeSection.value === 'structure' && currentProjectType.value) {
    return (
      currentProjectType.value.description ||
      defaultProjectDescriptions[currentProjectTypeKey.value] ||
      currentSectionMeta.value.description
    )
  }
  return currentSectionMeta.value.description
})

const activeGitignoreTemplate = computed(() => settings.value.privacy.gitignore_template || 'gitignore')

const suggestedGitignoreEntries = computed(() => {
  const entries = new Set()
  const types = settings.value.project_types || {}

  const sensitiveDirs = types.project_sensitive?.directories || {}
  for (const path of Object.values(sensitiveDirs)) {
    if (typeof path === 'string' && path.trim() && path.includes('private')) {
      entries.add(path.replace(/^\/+/, ''))
    }
  }

  const generalDirs = types.project?.directories || {}
  ;['cache', 'scratch'].forEach((key) => {
    const value = generalDirs[key]
    if (typeof value === 'string' && value.trim()) {
      entries.add(value.replace(/^\/+/, ''))
    }
  })

  return Array.from(entries).sort()
})

const canonicalTemplateName = computed(() => canonicalTemplateMap[settings.value.defaults.ai_canonical_file] || 'ai_claude')

const notebookScriptSubnav = [
  { id: 'notebooksScripts-format', label: 'Defaults' },
  { id: 'notebooksScripts-notebook-stub', label: 'Notebook Stub' },
  { id: 'notebooksScripts-script-stub', label: 'Script Stub' }
]

const buildSettingsHref = (sectionSlug, subsectionSlug) => {
  const params = { section: sectionSlug || undefined }
  if (subsectionSlug) params.subsection = subsectionSlug
  return router.resolve({ name: 'settings', params }).href
}

const pushSettingsRoute = (sectionSlug, subsectionSlug) => {
  const params = {}
  if (sectionSlug) params.section = sectionSlug
  if (subsectionSlug) params.subsection = subsectionSlug

  const currentSectionSlug = route.params.section || undefined
  const currentSubSlug = route.params.subsection || undefined
  const nextSectionSlug = params.section || undefined
  const nextSubSlug = params.subsection || undefined

  if (currentSectionSlug === nextSectionSlug && currentSubSlug === nextSubSlug) {
    return Promise.resolve()
  }

  return router.replace({ name: 'settings', params }).catch(() => {})
}

watch(
  () => route.params.section,
  (slug) => {
    if (!slug) {
      pushSettingsRoute(sectionSlugMap[defaultSectionId], undefined)
      return
    }

    const sectionId = sectionSlugToId[slug] || defaultSectionId
    activeSection.value = sectionId

    if (!sectionSlugToId[slug]) {
      pushSettingsRoute(sectionSlugMap[sectionId], undefined)
      return
    }

    // Allow structure section without subsection to show index page
    // No auto-redirect needed
  },
  { immediate: true }
)

// Removed watcher that forced redirect when no subsection
// Now allows index page to display when clicking Project Structure

const toScalar = (value, fallback = '') => {
  if (Array.isArray(value)) {
    return value.length > 0 ? toScalar(value[0], fallback) : fallback
  }
  return value ?? fallback
}

const toBoolean = (value, fallback = false) => {
  const scalar = toScalar(value, fallback)
  if (typeof scalar === 'boolean') return scalar
  if (typeof scalar === 'string') {
    return ['true', '1', 'yes'].includes(scalar.toLowerCase())
  }
  return Boolean(scalar)
}

const flattenArray = (value) => {
  if (!Array.isArray(value)) return []
  return value.flatMap((item) => (Array.isArray(item) ? item : [item])).filter(Boolean)
}

const normalizeDirectories = (dirs = {}, fallback = {}) => {
  const merged = { ...fallback }
  for (const [key, val] of Object.entries(dirs || {})) {
    const candidate = toScalar(val, null)
    if (candidate === null || candidate === '') {
      delete merged[key]
    } else {
      merged[key] = candidate
    }
  }
  return merged
}

const normalizeProjectType = (key, type) => {
  const fallback = defaultProjectTypes.value[key] || {
    directories: {},
    render_dirs: {},
    quarto: {},
    extra_directories: []
  }
  return {
    label: toScalar(type?.label, fallback.label || formatProjectTypeName(key)),
    description: toScalar(type?.description, fallback.description || ''),
    ggplot_theme: toScalar(type?.ggplot_theme, 'theme_minimal'),
    set_theme_on_scaffold: toBoolean(type?.set_theme_on_scaffold, false),
    // Don't merge with fallback - only use explicitly saved directories
    directories: normalizeDirectories(type?.directories, {}),
    // For render_dirs, merge with fallback defaults when empty
    render_dirs: normalizeDirectories(type?.render_dirs, fallback.render_dirs || {}),
    quarto: {
      render_dir: toScalar(type?.quarto?.render_dir, fallback.quarto?.render_dir || '.')
    },
    notebook_template: toScalar(type?.notebook_template, fallback.notebook_template || 'notebook'),
    extra_directories: Array.isArray(type?.extra_directories) ? type.extra_directories : (fallback.extra_directories || []),
    gitignore: toScalar(type?.gitignore, fallback.gitignore || '')
  }
}

const hydrateDefaultsFromCatalog = (catalogData) => {
  if (!catalogData || !catalogData.project_types) return

  console.log('[DEBUG] hydrateDefaultsFromCatalog - catalogData.project_types:', catalogData.project_types)
  console.log('[DEBUG] project gitignore from catalog:', catalogData.project_types.project?.gitignore?.substring(0, 100))

  const normalized = {}
  for (const [key, type] of Object.entries(catalogData.project_types)) {
    const fallback = fallbackProjectTypes[key] || {}
    const hydrated = hydrateStructureFromCatalog(
      type,
      {},
      fallback.directories || {},
      fallback.render_dirs || {}
    )
    const { directories, render_dirs } = hydrated

    normalized[key] = {
      label: toScalar(type.label, fallback.label || formatProjectTypeName(key)),
      description: toScalar(type.description, fallback.description || ''),
      directories,
      render_dirs,
      quarto: {
        render_dir: toScalar(type.quarto?.render_dir?.default, fallback.quarto?.render_dir || '.')
      },
      notebook_template: toScalar(type.notebook_template?.default, fallback.notebook_template || 'notebook'),
      optional_toggles: type.optional_toggles || {},
      gitignore: toScalar(type.gitignore, fallback.gitignore || '')
    }

    console.log(`[DEBUG] Normalized ${key} - gitignore length:`, normalized[key].gitignore?.length)
  }

  // Ensure any fallback types missing from catalog are preserved
  for (const [key, fallback] of Object.entries(fallbackProjectTypes)) {
    if (!normalized[key]) {
      normalized[key] = JSON.parse(JSON.stringify(fallback))
    }
  }

  defaultProjectTypes.value = normalized
}

const setPresentationDirectory = (dirKey, enabled, defaultPath) => {
  if (!settings.value.project_types?.presentation) return
  const dirs = settings.value.project_types.presentation.directories || (settings.value.project_types.presentation.directories = {})
  if (enabled) {
    if (!dirs[dirKey] || dirs[dirKey] === '') {
      dirs[dirKey] = defaultPath
    }
  } else {
    if (Object.prototype.hasOwnProperty.call(dirs, dirKey)) {
      delete dirs[dirKey]
    }
  }
}

const loadTemplateInline = async (templateName, editorKey = templateName) => {
  if (!templateEditors[editorKey]) return
  templateEditors[editorKey].loading = true
  try {
    const response = await fetch(`/api/templates/${templateName}`)
    if (!response.ok) throw new Error('Request failed')
    const data = await response.json()
    templateEditors[editorKey].contents = data.contents || ''
  } catch (error) {
    toast.error('Template Error', 'Unable to load template contents.')
  } finally {
    templateEditors[editorKey].loading = false
  }
}

const resetInlineTemplate = async (templateName, editorKey = templateName) => {
  if (!templateEditors[editorKey]) return
  try {
    const response = await fetch(`/api/templates/${templateName}`, { method: 'DELETE' })
    if (!response.ok) throw new Error('Request failed')
    await loadTemplateInline(templateName, editorKey)
    toast.success('Template Reset', 'Restored the packaged default template.')
  } catch (error) {
    toast.error('Reset Failed', 'Unable to restore the default template.')
  }
}

const resetCanonicalTemplateInline = () => {
  resetInlineTemplate(canonicalTemplateName.value, 'canonical')
}

watch(aiAssistants, (newVal) => {
  if (isLoadingSettings.value) {
    console.log('[watch:aiAssistants] Skipped - loading')
    return
  }
  console.log('[watch:aiAssistants] Triggered', newVal)
  const assistants = []
  if (newVal.claude) assistants.push('claude')
  if (newVal.copilot) assistants.push('copilot')
  if (newVal.agents) assistants.push('agents')
  settings.value.defaults.ai_assistants = assistants
}, { deep: true })

watch(() => settings.value.defaults.ai_canonical_file, async () => {
  if (isLoadingSettings.value) return
  await loadTemplateInline(canonicalTemplateName.value, 'canonical')
})

watch(() => settings.value.defaults.git_hooks.data_security, (val) => {
  if (isLoadingSettings.value) return
  if (settings.value.privacy.secret_scan !== val) {
    settings.value.privacy.secret_scan = val
  }
})

watch(() => settings.value.privacy.secret_scan, (val) => {
  if (isLoadingSettings.value) return
  if (settings.value.defaults.git_hooks.data_security !== val) {
    settings.value.defaults.git_hooks.data_security = val
  }
})

watch(() => presentationOptions.includeInputs, (enabled) => {
  if (isLoadingSettings.value) return
  setPresentationDirectory('inputs', enabled, presentationOptionalDefaults.value.inputs)
})

watch(() => presentationOptions.includeScripts, (enabled) => {
  if (isLoadingSettings.value) return
  setPresentationDirectory('scripts', enabled, presentationOptionalDefaults.value.scripts)
})

watch(() => presentationOptions.includeFunctions, (enabled) => {
  if (isLoadingSettings.value) return
  setPresentationDirectory('functions', enabled, presentationOptionalDefaults.value.functions)
})

// Watch directories enabled state and sync with settings
watch(directoriesEnabled, (newState) => {
  if (isLoadingSettings.value) return

  for (const [projectType, directories] of Object.entries(newState)) {
    if (!settings.value.project_types?.[projectType]) continue

    const settingsDirs = settings.value.project_types[projectType].directories || {}
    const settingsRenderDirs = settings.value.project_types[projectType].render_dirs || {}
    const catalogDirs = catalog.value?.project_types?.[projectType]?.directories || {}
    const catalogRenderDirs = catalog.value?.project_types?.[projectType]?.render_dirs || {}

    for (const [dirKey, enabled] of Object.entries(directories)) {
      if (enabled === false) {
        // Remove directory when disabled
        if (Object.prototype.hasOwnProperty.call(settingsDirs, dirKey)) {
          delete settings.value.project_types[projectType].directories[dirKey]
        }
        // Also remove render_dir if it exists
        if (Object.prototype.hasOwnProperty.call(settingsRenderDirs, dirKey)) {
          delete settings.value.project_types[projectType].render_dirs[dirKey]
        }
      } else if (enabled === true) {
        // Add directory when enabled (if not already present)
        if (!Object.prototype.hasOwnProperty.call(settingsDirs, dirKey)) {
          const defaultValue = catalogDirs[dirKey]?.default || ''
          settings.value.project_types[projectType].directories[dirKey] = defaultValue
        }
        // Add render_dir if this directory has one in the catalog
        if (catalogRenderDirs[dirKey] && !Object.prototype.hasOwnProperty.call(settingsRenderDirs, dirKey)) {
          const defaultRenderDir = catalogRenderDirs[dirKey]?.default || ''
          if (defaultRenderDir) {
            settings.value.project_types[projectType].render_dirs[dirKey] = defaultRenderDir
          }
        }
      }
    }
  }
}, { deep: true })

// Watch env variables to update groups
watch(defaultEnvVariables, (vars) => {
  if (isLoadingSettings.value) return
  defaultEnvGroups.value = groupEnvByPrefix(vars)
}, { deep: true })

const handleKeyDown = (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key === 's') {
    event.preventDefault()
    saveSettings()
  }
}

const hasDirectory = (typeKey, field) => {
  const dirs = settings.value.project_types?.[typeKey]?.directories
  return !!dirs && Object.prototype.hasOwnProperty.call(dirs, field)
}

const showResetConfirm = (key) => {
  if (!defaultProjectTypes.value[key]) return
  resetConfirmModal.projectTypeKey = key
  resetConfirmModal.projectTypeName = settings.value.project_types[key]?.label || formatProjectTypeName(key)
  resetConfirmModal.open = true
}

const resetProjectType = () => {
  const key = resetConfirmModal.projectTypeKey
  if (!defaultProjectTypes.value[key]) return

  settings.value.project_types[key] = JSON.parse(JSON.stringify(defaultProjectTypes.value[key]))
  if (key === 'presentation') {
    presentationOptions.includeInputs = false
    presentationOptions.includeScripts = false
    presentationOptions.includeFunctions = false
  }

  // Close modal and show success
  resetConfirmModal.open = false
  toast.success('Reset Complete', `${resetConfirmModal.projectTypeName} has been reset to defaults`)
}

const openTemplateEditor = async (name, { title, description }) => {
  templateModal.open = true
  templateModal.loading = true
  templateModal.name = name
  templateModal.title = title
  templateModal.description = description
  try {
    const response = await fetch(`/api/templates/${name}`)
    const data = await response.json()
    templateModal.contents = data.contents || ''
  } catch (error) {
    toast.error('Template Error', 'Unable to load template contents.')
  } finally {
    templateModal.loading = false
  }
}

const openCanonicalTemplate = () => {
  const name = canonicalTemplateMap[settings.value.defaults.ai_canonical_file] || 'ai_claude'
  openTemplateEditor(name, {
    title: `Edit ${settings.value.defaults.ai_canonical_file}`,
    description: 'This file is treated as canonical; other assistant files are synced to it.'
  })
}

const resetTemplate = async (name) => {
  try {
    await fetch(`/api/templates/${name}`, { method: 'DELETE' })
    toast.success('Template Reset', 'Restored the packaged default template.')
  } catch (error) {
    toast.error('Reset Failed', 'Unable to restore the default template.')
  }
}

const resetCanonicalTemplate = () => {
  const name = canonicalTemplateMap[settings.value.defaults.ai_canonical_file] || 'ai_claude'
  resetTemplate(name)
}

const saveTemplate = async () => {
  try {
    templateModal.loading = true
    await fetch(`/api/templates/${templateModal.name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contents: templateModal.contents })
    })
    toast.success('Template Saved', 'Your changes have been saved.')
    templateModal.open = false
  } catch (error) {
    toast.error('Save Failed', 'Could not save template changes.')
  } finally {
    templateModal.loading = false
  }
}

const scrollToSection = (id) => {
  const el = document.getElementById(id)
  if (el) {
    el.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }
}

const defaultProjectSectionId = (key) => {
  switch (key) {
    case 'project':
      return `project-${key}-inputs`
    case 'project_sensitive':
      return `project-${key}-workspaces`
    case 'presentation':
      return `project-${key}-primary`
    case 'course':
      return `project-${key}-core`
    default:
      return `project-${key}`
  }
}

// Determine if a section should show as active (with blue background)
// Parent sections should NOT be active when a sub-item is selected
const isSectionActive = (sectionId) => {
  if (activeSection.value !== sectionId) return false

  // For structure section, only active if no project type is selected
  if (sectionId === 'structure' && currentProjectTypeKey.value) {
    return false
  }

  // For templates section, only active if no template is selected
  // (templates always has a selection, so parent is never "active")
  if (sectionId === 'templates') {
    return false
  }

  return true
}

const navigateToSection = async (sectionId) => {
  const section = sections.find((s) => s.id === sectionId)
  if (!section) return

  // For structure section, go to index page (no subsection)
  const subsectionSlug = section.id === 'structure'
    ? undefined
    : section.id === 'templates'
      ? (route.params.subsection || selectedTemplate.value || 'notebook')
      : undefined

  await pushSettingsRoute(section.slug, subsectionSlug)
  await nextTick()

  scrollToSection(section.id)
}

const navigateToProjectType = async (key) => {
  const slug = projectTypeSlugMap[key] || projectTypeSlugMap[defaultProjectTypeKey]
  await pushSettingsRoute('project-structure', slug)
  await nextTick()
  scrollToSection(defaultProjectSectionId(key))
}

watch(
  () => currentProjectTypeKey.value,
  (key, prev) => {
    if (activeSection.value !== 'structure') return
    if (!key || key === prev) return
    nextTick(() => scrollToSection(defaultProjectSectionId(key)))
  }
)

watch(
  () => route.params.subsection,
  async (slug) => {
    if (route.params.section !== 'templates') return
    const next = slug || 'notebook'
    if (selectedTemplate.value !== next) {
      selectedTemplate.value = next
    }
    await nextTick()
    scrollToSection('templates')
  }
)


const loadSettings = async () => {
  try {
    console.log('[loadSettings] Starting load, setting isLoadingSettings = true')
    isLoadingSettings.value = true
    const [catalogResponse, settingsResponse] = await Promise.all([
      fetch('/api/settings/catalog'),
      fetch('/api/settings/get')
    ])

    if (!catalogResponse.ok) {
      throw new Error('Failed to load settings catalog')
    }

    if (!settingsResponse.ok) {
      throw new Error('Failed to load settings payload')
    }

    console.log('[loadSettings] Responses received, parsing JSON')
    const catalogData = await catalogResponse.json()
    catalog.value = catalogData
    hydrateDefaultsFromCatalog(catalogData)

    const data = await settingsResponse.json()
    console.log('[loadSettings] Settings data:', data)
    console.log('[loadSettings] data.global:', data.global)
    console.log('[loadSettings] data.global?.projects_root:', data.global?.projects_root)

    // V2 format: projects_root is under global
    const loadedProjectsRoot = toScalar(data.global?.projects_root || data.projects_root, '')
    console.log('[loadSettings] Setting projects_root to:', loadedProjectsRoot)
    settings.value.projects_root = loadedProjectsRoot

    if (data.project_types) {
      const merged = {}
      const rawTypes = { ...defaultProjectTypes.value, ...data.project_types }
      for (const [key, value] of Object.entries(rawTypes)) {
        merged[key] = normalizeProjectType(key, value)
      }
      settings.value.project_types = merged

      // Ensure render_dirs exists for all project types
      for (const key of Object.keys(settings.value.project_types)) {
        if (!settings.value.project_types[key].render_dirs) {
          settings.value.project_types[key].render_dirs = {}
        }
      }
    }

    presentationOptions.includeInputs = hasDirectory('presentation', 'inputs')
    presentationOptions.includeScripts = hasDirectory('presentation', 'scripts')
    presentationOptions.includeFunctions = hasDirectory('presentation', 'functions')

    // Initialize directories enabled state for all project types
    for (const projectType of ['project', 'project_sensitive', 'course', 'presentation']) {
      const dirs = settings.value.project_types?.[projectType]?.directories || {}
      const catalogDirs = catalogData?.project_types?.[projectType]?.directories || {}
      const enabled = getDirectoriesEnabled(projectType)

      // Set all known directories from catalog
      // Priority: saved directories_enabled > catalog enabled_by_default > whether dir exists
      const savedEnabled = settings.value.project_types?.[projectType]?.directories_enabled || {}
      for (const dirKey of Object.keys(catalogDirs)) {
        const catalogDir = catalogDirs[dirKey]
        // Check if we have a saved enabled state first
        if (dirKey in savedEnabled) {
          enabled[dirKey] = savedEnabled[dirKey]
        } else {
          // Fall back to enabled_by_default from catalog, then whether dir exists in settings
          const enabledByDefault = catalogDir.enabled_by_default ?? Object.prototype.hasOwnProperty.call(dirs, dirKey)
          enabled[dirKey] = enabledByDefault
        }
      }

      // Also check for any extra directories in settings not in catalog
      for (const dirKey of Object.keys(dirs)) {
        if (!Object.prototype.hasOwnProperty.call(catalogDirs, dirKey)) {
          enabled[dirKey] = true
        }
      }

      // Initialize extra_directories as enabled by default
      const extraDirs = settings.value.project_types?.[projectType]?.extra_directories || []
      extraDirs.forEach(dir => {
        if (dir.key) {
          // Check if explicitly disabled, otherwise enable
          if (settings.value.project_types[projectType].directories_enabled &&
              settings.value.project_types[projectType].directories_enabled[dir.key] === false) {
            enabled[dir.key] = false
          } else {
            enabled[dir.key] = true
          }
        }
      })
    }

    if (data.author) {
      settings.value.author = {
        name: toScalar(data.author.name, ''),
        email: toScalar(data.author.email, ''),
        affiliation: toScalar(data.author.affiliation, '')
      }
    }

    if (data.defaults) {
      const defaults = data.defaults
      settings.value.defaults.project_type = toScalar(defaults.project_type, 'project')
      settings.value.defaults.notebook_format = toScalar(defaults.notebook_format, 'quarto')
      settings.value.defaults.ide = toScalar(defaults.ide, 'vscode')
      settings.value.defaults.positron = toBoolean(defaults.positron, false)
      settings.value.defaults.use_git = toBoolean(defaults.use_git, true)
      settings.value.defaults.use_renv = toBoolean(defaults.use_renv, false)
      // seed_on_scaffold and seed are now loaded from nested scaffold object below
      settings.value.defaults.ai_support = toBoolean(defaults.ai_support, true)
      settings.value.defaults.ai_canonical_file = toScalar(defaults.ai_canonical_file, 'CLAUDE.md')
      const assistants = flattenArray(defaults.ai_assistants)
      if (assistants.length) {
        settings.value.defaults.ai_assistants = assistants
        aiAssistants.claude = assistants.includes('claude')
        aiAssistants.copilot = assistants.includes('copilot')
        aiAssistants.agents = assistants.includes('agents')
      }

      if (defaults.git_hooks) {
        settings.value.defaults.git_hooks = {
          ...settings.value.defaults.git_hooks,
          ...Object.fromEntries(
            Object.entries(defaults.git_hooks).map(([key, val]) => [key, toBoolean(val, settings.value.defaults.git_hooks[key])])
          )
        }
        settings.value.privacy.secret_scan = settings.value.defaults.git_hooks.data_security
      }

      // Load scaffold settings (v2 nested structure)
      if (defaults.scaffold) {
        settings.value.defaults.scaffold = {
          source_all_functions: toBoolean(defaults.scaffold.source_all_functions, true),
          set_theme_on_scaffold: toBoolean(defaults.scaffold.set_theme_on_scaffold, false),
          ggplot_theme: toScalar(defaults.scaffold.ggplot_theme, 'theme_minimal'),
          seed_on_scaffold: toBoolean(defaults.scaffold.seed_on_scaffold, false),
          seed: toScalar(defaults.scaffold.seed, '123')
        }
      }

      // Load packages - use saved settings, or fall back to catalog defaults
      if (defaults.packages && defaults.packages.default_packages?.length) {
        settings.value.defaults.packages = normalizeDefaultPackages(defaults.packages)
      } else if (catalogData?.defaults?.packages) {
        // Fall back to catalog defaults when no saved packages
        settings.value.defaults.packages = normalizeDefaultPackages(catalogData.defaults.packages)
      }

      // Load quarto settings
      if (defaults.quarto) {
        settings.value.defaults.quarto = {
          html: {
            format: 'html',
            embed_resources: toBoolean(defaults.quarto.html?.embed_resources, true),
            theme: toScalar(defaults.quarto.html?.theme, 'default'),
            toc: toBoolean(defaults.quarto.html?.toc, true),
            toc_depth: parseInt(defaults.quarto.html?.toc_depth) || 3,
            code_fold: toBoolean(defaults.quarto.html?.code_fold, false),
            code_tools: toBoolean(defaults.quarto.html?.code_tools, false),
            highlight_style: toScalar(defaults.quarto.html?.highlight_style, 'github')
          },
          revealjs: {
            format: 'revealjs',
            theme: toScalar(defaults.quarto.revealjs?.theme, 'default'),
            incremental: toBoolean(defaults.quarto.revealjs?.incremental, false),
            slide_number: toBoolean(defaults.quarto.revealjs?.slide_number, true),
            transition: toScalar(defaults.quarto.revealjs?.transition, 'slide'),
            background_transition: toScalar(defaults.quarto.revealjs?.background_transition, 'fade'),
            controls: toBoolean(defaults.quarto.revealjs?.controls, true),
            progress: toBoolean(defaults.quarto.revealjs?.progress, true),
            center: toBoolean(defaults.quarto.revealjs?.center, true),
            highlight_style: toScalar(defaults.quarto.revealjs?.highlight_style, 'github')
          }
        }
      }

      // Keep legacy directories around for backwards compatibility
      if (defaults.directories) {
        settings.value.defaults.directories = {
          ...settings.value.defaults.directories,
          ...Object.fromEntries(
            Object.entries(defaults.directories).map(([key, val]) => [key, toScalar(val, settings.value.defaults.directories[key] || '')])
          )
        }
      } else if (settings.value.project_types.project) {
        settings.value.defaults.directories = {
          ...settings.value.defaults.directories,
          ...settings.value.project_types.project.directories
        }
      }

      initializeDefaultEnv(defaults.env)
      hydrateDefaultConnections(defaults.connections)
    }

    if (!data.defaults) {
      initializeDefaultEnv(null)
      hydrateDefaultConnections(null)
      // Load packages from catalog when no saved defaults
      if (catalogData?.defaults?.packages) {
        settings.value.defaults.packages = normalizeDefaultPackages(catalogData.defaults.packages)
      }
    }

    if (data.git) {
      settings.value.git = {
        user_name: toScalar(data.git.user_name, ''),
        user_email: toScalar(data.git.user_email, '')
      }
    }

    if (data.privacy) {
      settings.value.privacy.secret_scan = toBoolean(data.privacy.secret_scan, settings.value.defaults.git_hooks.data_security)
      settings.value.privacy.gitignore_template = toScalar(data.privacy.gitignore_template, 'gitignore')
    } else {
      settings.value.privacy.secret_scan = settings.value.defaults.git_hooks.data_security
    }

    await loadTemplateInline(canonicalTemplateName.value, 'canonical')
    console.log('[loadSettings] Load complete, about to set isLoadingSettings = false')
  } catch (error) {
    console.error('[loadSettings] Error during load:', error)
    toast.error('Load Failed', 'Unable to load current settings.')
  } finally {
    isLoadingSettings.value = false
    console.log('[loadSettings] isLoadingSettings now false')
  }
}

const gitPanelModel = computed({
  get() {
    const defaults = settings.value.defaults || {}
    const git = settings.value.git || {}
    const author = settings.value.author || {}
    return buildGitPanelModel({
      useGit: defaults.use_git,
      gitHooks: defaults.git_hooks,
      git,
      author
    })
  },
  set(val) {
    if (isLoadingSettings.value) {
      console.log('[gitPanelModel setter] Blocked during load')
      return
    }
    settings.value.defaults.git_hooks = settings.value.defaults.git_hooks || {}
    settings.value.git = settings.value.git || {}
    settings.value.author = settings.value.author || {}
    applyGitPanelModel(
      {
        gitTarget: settings.value.git,
        gitHooksTarget: settings.value.defaults.git_hooks,
        setUseGit: (val) => { settings.value.defaults.use_git = val },
        authorTarget: settings.value.author
      },
      val
    )
  }
})

const scaffoldPanelModel = computed({
  get() {
    const scaffold = settings.value.defaults?.scaffold || {}
    return {
      source_all_functions: scaffold.source_all_functions !== false,
      set_theme_on_scaffold: scaffold.set_theme_on_scaffold === true,
      ggplot_theme: scaffold.ggplot_theme || 'theme_minimal',
      seed_on_scaffold: scaffold.seed_on_scaffold || false,
      seed: scaffold.seed || '123'
    }
  },
  set(val) {
    if (isLoadingSettings.value) {
      console.log('[scaffoldPanelModel setter] Blocked during load')
      return
    }
    settings.value.defaults.scaffold = {
      ...(settings.value.defaults.scaffold || {}),
      source_all_functions: val.source_all_functions,
      set_theme_on_scaffold: val.set_theme_on_scaffold,
      ggplot_theme: val.ggplot_theme,
      seed_on_scaffold: val.seed_on_scaffold,
      seed: val.seed
    }
  }
})

// Helper functions for extra_directories
// Generic function for non-sensitive project types (returns all directories of a type)
const extraDirectoriesByType = (projectTypeKey, type) => {
  const projectType = settings.value.project_types[projectTypeKey]
  if (!projectType || !Array.isArray(projectType.extra_directories)) {
    return []
  }
  return projectType.extra_directories.filter(dir => dir.type === type)
}

// Sensitive project type functions - distinguish between saved and new
const savedExtraDirectoriesByType = (projectTypeKey, type) => {
  const projectType = settings.value.project_types[projectTypeKey]
  if (!projectType || !Array.isArray(projectType.extra_directories)) {
    return []
  }
  return projectType.extra_directories.filter(dir =>
    dir.type === type && !newExtraDirectoryIds.value.has(dir._id)
  )
}

const newExtraDirectoriesByType = (projectTypeKey, type) => {
  const projectType = settings.value.project_types[projectTypeKey]
  if (!projectType || !Array.isArray(projectType.extra_directories)) {
    return []
  }
  return projectType.extra_directories.filter(dir =>
    dir.type === type && newExtraDirectoryIds.value.has(dir._id)
  )
}

const updateExtraDirectories = (projectTypeKey, type, updatedItems) => {
  const projectType = settings.value.project_types[projectTypeKey]
  if (!projectType) return

  // Initialize if needed
  if (!Array.isArray(projectType.extra_directories)) {
    projectType.extra_directories = []
  }

  // Remove all items of this type
  const otherTypes = projectType.extra_directories.filter(dir => dir && dir.type !== type)

  // Add the updated items (ensuring they all have the correct type)
  const itemsWithType = updatedItems.map(item => ({ ...item, type }))

  // Replace entire array
  projectType.extra_directories = [...otherTypes, ...itemsWithType]
}

const updateExtraDirectoryPath = (projectTypeKey, key, newPath) => {
  const projectType = settings.value.project_types[projectTypeKey]
  if (!projectType || !Array.isArray(projectType.extra_directories)) return

  const dir = projectType.extra_directories.find(d => d.key === key)
  if (dir) {
    dir.path = newPath
  }
}

const updateNewExtraDirectoryField = (projectTypeKey, index, field, value) => {
  const projectType = settings.value.project_types[projectTypeKey]
  if (!projectType || !Array.isArray(projectType.extra_directories)) return

  const newDirs = projectType.extra_directories.filter(dir =>
    newExtraDirectoryIds.value.has(dir._id)
  )

  if (newDirs[index]) {
    newDirs[index][field] = value
  }
}

const addExtraDirectory = (projectTypeKey, type) => {
  const projectType = settings.value.project_types[projectTypeKey]
  if (!projectType) return

  if (!Array.isArray(projectType.extra_directories)) {
    projectType.extra_directories = []
  }

  // Create new directory entry
  const newDir = {
    key: '',
    label: '',
    path: '',
    type,
    _id: Date.now()
  }

  projectType.extra_directories.push(newDir)
  newExtraDirectoryIds.value.add(newDir._id)
}

const removeExtraDirectory = (projectTypeKey, index) => {
  const projectType = settings.value.project_types[projectTypeKey]
  if (!projectType || !Array.isArray(projectType.extra_directories)) return

  const newDirs = projectType.extra_directories.filter(dir =>
    newExtraDirectoryIds.value.has(dir._id)
  )

  if (newDirs[index]) {
    const dirToRemove = newDirs[index]
    // Remove from tracking
    newExtraDirectoryIds.value.delete(dirToRemove._id)
    // Remove from array
    const idx = projectType.extra_directories.indexOf(dirToRemove)
    if (idx !== -1) {
      projectType.extra_directories.splice(idx, 1)
    }
  }
}

// Computed properties for v-model binding with Repeater component
const newInputPrivateDirectories = computed({
  get() {
    return newExtraDirectoriesByType(currentProjectTypeKey.value, 'input_private')
  },
  set(value) {
    const projectType = settings.value.project_types[currentProjectTypeKey.value]
    if (!projectType) return

    // Get the current new items before update
    const currentNewItems = newExtraDirectoriesByType(currentProjectTypeKey.value, 'input_private')

    // Find items that were deleted
    const deletedItems = currentNewItems.filter(current =>
      !value.some(v => v._id === current._id)
    )

    // Remove deleted items from tracking
    deletedItems.forEach(item => {
      if (item._id) {
        newExtraDirectoryIds.value.delete(item._id)
      }
    })

    // Get saved items of this type (not in the new Set)
    const savedItems = savedExtraDirectoriesByType(currentProjectTypeKey.value, 'input_private')

    // Merge saved + new items
    const merged = [...savedItems, ...value]

    // Update with merged array
    updateExtraDirectories(currentProjectTypeKey.value, 'input_private', merged)

    // Track new items
    value.forEach(item => {
      if (item._id && !newExtraDirectoryIds.value.has(item._id)) {
        newExtraDirectoryIds.value.add(item._id)
      }
    })
  }
})

const newInputPublicDirectories = computed({
  get() {
    return newExtraDirectoriesByType(currentProjectTypeKey.value, 'input_public')
  },
  set(value) {
    const projectType = settings.value.project_types[currentProjectTypeKey.value]
    if (!projectType) return

    const currentNewItems = newExtraDirectoriesByType(currentProjectTypeKey.value, 'input_public')
    const deletedItems = currentNewItems.filter(current =>
      !value.some(v => v._id === current._id)
    )
    deletedItems.forEach(item => {
      if (item._id) {
        newExtraDirectoryIds.value.delete(item._id)
      }
    })

    const savedItems = savedExtraDirectoriesByType(currentProjectTypeKey.value, 'input_public')
    const merged = [...savedItems, ...value]
    updateExtraDirectories(currentProjectTypeKey.value, 'input_public', merged)

    value.forEach(item => {
      if (item._id && !newExtraDirectoryIds.value.has(item._id)) {
        newExtraDirectoryIds.value.add(item._id)
      }
    })
  }
})

const newOutputPrivateDirectories = computed({
  get() {
    return newExtraDirectoriesByType(currentProjectTypeKey.value, 'output_private')
  },
  set(value) {
    const projectType = settings.value.project_types[currentProjectTypeKey.value]
    if (!projectType) return

    const savedItems = savedExtraDirectoriesByType(currentProjectTypeKey.value, 'output_private')
    const merged = [...savedItems, ...value]
    updateExtraDirectories(currentProjectTypeKey.value, 'output_private', merged)

    value.forEach(item => {
      if (item._id && !newExtraDirectoryIds.value.has(item._id)) {
        newExtraDirectoryIds.value.add(item._id)
      }
    })
  }
})

const newOutputPublicDirectories = computed({
  get() {
    return newExtraDirectoriesByType(currentProjectTypeKey.value, 'output_public')
  },
  set(value) {
    const projectType = settings.value.project_types[currentProjectTypeKey.value]
    if (!projectType) return

    const savedItems = savedExtraDirectoriesByType(currentProjectTypeKey.value, 'output_public')
    const merged = [...savedItems, ...value]
    updateExtraDirectories(currentProjectTypeKey.value, 'output_public', merged)

    value.forEach(item => {
      if (item._id && !newExtraDirectoryIds.value.has(item._id)) {
        newExtraDirectoryIds.value.add(item._id)
      }
    })
  }
})

const newWorkspaceDirectories = computed({
  get() {
    return newExtraDirectoriesByType(currentProjectTypeKey.value, 'workspace')
  },
  set(value) {
    const projectType = settings.value.project_types[currentProjectTypeKey.value]
    if (!projectType) return

    // Get the current new items before update
    const currentNewItems = newExtraDirectoriesByType(currentProjectTypeKey.value, 'workspace')

    // Find items that were deleted (in current but not in new value)
    const deletedItems = currentNewItems.filter(current =>
      !value.some(v => v._id === current._id)
    )

    // Remove deleted items from tracking
    deletedItems.forEach(item => {
      if (item._id) {
        newExtraDirectoryIds.value.delete(item._id)
      }
    })

    const savedItems = savedExtraDirectoriesByType(currentProjectTypeKey.value, 'workspace')
    const merged = [...savedItems, ...value]
    updateExtraDirectories(currentProjectTypeKey.value, 'workspace', merged)

    // Track new items
    value.forEach(item => {
      if (item._id && !newExtraDirectoryIds.value.has(item._id)) {
        newExtraDirectoryIds.value.add(item._id)
      }
    })
  }
})

const newInputDirectories = computed({
  get() {
    return newExtraDirectoriesByType(currentProjectTypeKey.value, 'input')
  },
  set(value) {
    const projectType = settings.value.project_types[currentProjectTypeKey.value]
    if (!projectType) return

    // Get the current new items before update
    const currentNewItems = newExtraDirectoriesByType(currentProjectTypeKey.value, 'input')

    // Find items that were deleted (in current but not in new value)
    const deletedItems = currentNewItems.filter(current =>
      !value.some(v => v._id === current._id)
    )

    // Remove deleted items from tracking
    deletedItems.forEach(item => {
      if (item._id) {
        newExtraDirectoryIds.value.delete(item._id)
      }
    })

    const savedItems = savedExtraDirectoriesByType(currentProjectTypeKey.value, 'input')
    const merged = [...savedItems, ...value]
    updateExtraDirectories(currentProjectTypeKey.value, 'input', merged)

    // Track new items
    value.forEach(item => {
      if (item._id && !newExtraDirectoryIds.value.has(item._id)) {
        newExtraDirectoryIds.value.add(item._id)
      }
    })
  }
})

const newOutputDirectories = computed({
  get() {
    return newExtraDirectoriesByType(currentProjectTypeKey.value, 'output')
  },
  set(value) {
    const projectType = settings.value.project_types[currentProjectTypeKey.value]
    if (!projectType) return

    // Get the current new items before update
    const currentNewItems = newExtraDirectoriesByType(currentProjectTypeKey.value, 'output')

    // Find items that were deleted (in current but not in new value)
    const deletedItems = currentNewItems.filter(current =>
      !value.some(v => v._id === current._id)
    )

    // Remove deleted items from tracking
    deletedItems.forEach(item => {
      if (item._id) {
        newExtraDirectoryIds.value.delete(item._id)
      }
    })

    const savedItems = savedExtraDirectoriesByType(currentProjectTypeKey.value, 'output')
    const merged = [...savedItems, ...value]
    updateExtraDirectories(currentProjectTypeKey.value, 'output', merged)

    // Track new items
    value.forEach(item => {
      if (item._id && !newExtraDirectoryIds.value.has(item._id)) {
        newExtraDirectoryIds.value.add(item._id)
      }
    })
  }
})

// Validation helpers for extra_directories
const validateExtraDirectoryKey = (key, projectTypeKey, type, currentIndex) => {
  if (!key) return null // Empty is ok, will be caught by backend

  // Check format (alphanumeric + underscore only)
  if (!/^[a-zA-Z0-9_]+$/.test(key)) {
    return 'Only letters, numbers, and underscores allowed'
  }

  // Check for duplicates across ALL extra_directories (not just this type)
  const projectType = settings.value.project_types[projectTypeKey]
  if (!projectType || !Array.isArray(projectType.extra_directories)) {
    return null
  }

  // Get all items of the current type
  const itemsOfType = projectType.extra_directories.filter(dir => dir.type === type)

  // Check for duplicates within the same type
  const duplicateInType = itemsOfType.findIndex((item, idx) =>
    idx !== currentIndex && item.key === key
  )
  if (duplicateInType !== -1) {
    return 'Duplicate key within this section'
  }

  // Check for duplicates across different types
  const allOtherItems = projectType.extra_directories.filter(dir => dir.type !== type)
  const duplicateAcrossTypes = allOtherItems.find(item => item.key === key)
  if (duplicateAcrossTypes) {
    return `Key already used in ${duplicateAcrossTypes.type} directories`
  }

  return null
}

const validateExtraDirectoryPath = (path) => {
  if (!path || path.trim() === '') {
    return null // Will be filtered out on save
  }

  // Check for absolute path
  if (path.startsWith('/')) {
    return 'Must be relative (no leading slash)'
  }

  // Check for path traversal
  if (path.includes('..')) {
    return 'Path traversal not allowed (..)'
  }

  return null
}

const validateExtraDirectoryLabel = (label) => {
  if (!label || label.trim() === '') {
    return null // Will be filtered out on save
  }
  return null
}

const clone = (value) => JSON.parse(JSON.stringify(value || {}))

const initializeDefaultEnv = (envConfig) => {
  const normalized = normalizeEnvConfig(envConfig, DEFAULT_ENV_TEMPLATE)
  defaultEnvRawContent.value = normalized.rawContent
  defaultEnvVariables.value = normalized.variables
  defaultEnvGroups.value = normalized.groups
  defaultEnvViewMode.value = normalized.viewMode
}

const hydrateDefaultConnections = (connectionsConfig) => {
  const mapped = mapConnectionsToArrays(connectionsConfig || {})
  databaseConnections.value = mapped.databaseConnections
  s3Connections.value = mapped.s3Connections
  defaultDatabase.value = mapped.defaultDatabase
  defaultStorageBucket.value = mapped.defaultStorageBucket
}

const resetEnvDefaults = () => {
  defaultEnvRawContent.value = DEFAULT_ENV_TEMPLATE
  defaultEnvVariables.value = parseEnvContent(DEFAULT_ENV_TEMPLATE)
  defaultEnvGroups.value = groupEnvByPrefix(parseEnvContent(DEFAULT_ENV_TEMPLATE))
  defaultEnvViewMode.value = 'grouped'
}

const saveSettings = async () => {
  try {
    saving.value = true

    const normalizedRoot = settings.value.projects_root?.trim() || ''
    console.log('[saveSettings] settings.value.projects_root:', settings.value.projects_root)
    console.log('[saveSettings] normalizedRoot:', normalizedRoot)

    const payload = JSON.parse(JSON.stringify(settings.value))

    // V2 format: projects_root goes under global, not at root
    if (!payload.global) payload.global = {}
    payload.global.projects_root = normalizedRoot ? normalizedRoot : null
    delete payload.projects_root  // Remove root-level if it exists

    console.log('[saveSettings] payload.global.projects_root:', payload.global.projects_root)

    // Handle scaffold seed (v2 nested structure)
    if (payload.defaults.scaffold) {
      payload.defaults.scaffold.seed = payload.defaults.scaffold.seed ?? ''
    }
    // Also handle flat structure for backward compatibility
    payload.defaults.seed = payload.defaults.seed ?? ''

  // Handle nested packages structure
  payload.defaults.packages = mapDefaultPackagesToPayload(settings.value.defaults.packages)

    // Save .env defaults
    payload.defaults.env = { raw: defaultEnvRawContent.value || '' }

    // Connections payload
    payload.defaults.connections = mapConnectionsToPayload({
      databaseConnections: databaseConnections.value,
      s3Connections: s3Connections.value,
      defaultDatabase: defaultDatabase.value,
      defaultStorageBucket: defaultStorageBucket.value
    })

    payload.defaults.directories = payload.project_types?.project?.directories || payload.defaults.directories
    payload.defaults.git_hooks.data_security = payload.privacy.secret_scan
    payload.git = payload.git || { user_name: '', user_email: '' }

    // Normalize structure payload per project type
    for (const projectTypeKey in payload.project_types) {
      const catalogDirs = catalog.value?.project_types?.[projectTypeKey]?.directories || {}
      const enabledState = directoriesEnabled[projectTypeKey] || payload.project_types[projectTypeKey].directories_enabled || {}
      const serialized = serializeStructureForSave({
        catalogDirs,
        directories: payload.project_types[projectTypeKey].directories || {},
        render_dirs: payload.project_types[projectTypeKey].render_dirs || {},
        enabled: enabledState,
        extra_directories: payload.project_types[projectTypeKey].extra_directories || []
      })
      payload.project_types[projectTypeKey].directories = serialized.directories
      payload.project_types[projectTypeKey].render_dirs = serialized.render_dirs
      payload.project_types[projectTypeKey].directories_enabled = serialized.enabled
      payload.project_types[projectTypeKey].extra_directories = serialized.extra_directories
    }

    const response = await fetch('/api/settings/save', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })

    if (!response.ok) {
      const errorText = await response.text()
      throw new Error('Failed to save settings')
    }

    const responseData = await response.json()

    const templateResponses = await Promise.all([
      fetch('/api/templates/notebook', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ contents: templateEditors.notebook.contents })
      }),
      fetch('/api/templates/script', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ contents: templateEditors.script.contents })
      }),
      fetch('/api/templates/presentation', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ contents: templateEditors.presentation.contents })
      }),
      fetch('/api/templates/gitignore-project', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ contents: templateEditors.gitignore_project.contents })
      }),
      fetch('/api/templates/gitignore-project_sensitive', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ contents: templateEditors.gitignore_project_sensitive.contents })
      }),
      fetch('/api/templates/gitignore-course', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ contents: templateEditors.gitignore_course.contents })
      }),
      fetch('/api/templates/gitignore-presentation', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ contents: templateEditors.gitignore_presentation.contents })
      }),
      fetch(`/api/templates/${canonicalTemplateName.value}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ contents: templateEditors.canonical.contents })
      })
    ])

    if (templateResponses.some((res) => !res.ok)) {
      throw new Error('Template save failed')
    }

    // Clear new directory tracking - they're now saved
    newExtraDirectoryIds.value.clear()

    console.log('[saveSettings] Before loadSettings, projects_root was:', settings.value.projects_root)

    // Reload settings to get fresh data from server
    await loadSettings()

    console.log('[saveSettings] After loadSettings, projects_root is:', settings.value.projects_root)

    toast.success('Settings Saved', 'Your global defaults were updated.')
  } catch (error) {
    console.error('Failed to save settings:', error)
    toast.error('Save Failed', error?.message || 'Review your changes and try again.')
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  loadSettings()
  loadTemplateInline('notebook')
  loadTemplateInline('script')
  loadTemplateInline('presentation')
  loadTemplateInline('gitignore-project', 'gitignore_project')
  loadTemplateInline('gitignore-project_sensitive', 'gitignore_project_sensitive')
  loadTemplateInline('gitignore-course', 'gitignore_course')
  loadTemplateInline('gitignore-presentation', 'gitignore_presentation')
  loadTemplateInline(canonicalTemplateName.value, 'canonical')

  // Ensure templates route has a subsection slug
  if (route.params.section === 'templates' && !route.params.subsection) {
    pushSettingsRoute('templates', selectedTemplate.value || 'notebook')
  }

  window.addEventListener('keydown', handleKeyDown)
})

onUnmounted(() => {
  window.removeEventListener('keydown', handleKeyDown)
})
</script>
